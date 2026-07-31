import 'dart:collection';

import '../../domain/matching/matching_policy.dart';
import '../../domain/return_route/route_anchor_result.dart';

class ReturnRouteMatchResult {
  final bool subscriptionActive;
  final bool driverIdentityCompatible;
  final bool returnRouteReady;
  final RouteAnchorResult? anchors;
  final RouteDeviationResult? deviation;
  final MatchingEvaluationResult? matchingEvaluation;
  final List<String> rejectionReasons;

  const ReturnRouteMatchResult._({
    required this.subscriptionActive,
    required this.driverIdentityCompatible,
    required this.returnRouteReady,
    required this.anchors,
    required this.deviation,
    required this.matchingEvaluation,
    required this.rejectionReasons,
  });

  factory ReturnRouteMatchResult.rejectedBeforeMeasurement({
    required bool subscriptionActive,
    required bool driverIdentityCompatible,
    required bool returnRouteReady,
    RouteAnchorResult? anchors,
    required Iterable<String> rejectionReasons,
  }) {
    final normalizedReasons = _normalizeReasons(rejectionReasons);
    if (normalizedReasons.isEmpty) {
      throw ArgumentError(
        'Ölçüm öncesi ret için en az bir neden gereklidir.',
        'rejectionReasons',
      );
    }

    return ReturnRouteMatchResult._(
      subscriptionActive: subscriptionActive,
      driverIdentityCompatible: driverIdentityCompatible,
      returnRouteReady: returnRouteReady,
      anchors: anchors,
      deviation: null,
      matchingEvaluation: null,
      rejectionReasons: normalizedReasons,
    );
  }

  factory ReturnRouteMatchResult.evaluated({
    required RouteAnchorResult anchors,
    required RouteDeviationResult deviation,
    required MatchingEvaluationResult matchingEvaluation,
  }) {
    return ReturnRouteMatchResult._(
      subscriptionActive: true,
      driverIdentityCompatible: true,
      returnRouteReady: true,
      anchors: anchors,
      deviation: deviation,
      matchingEvaluation: matchingEvaluation,
      rejectionReasons: _normalizeReasons(matchingEvaluation.rejectionReasons),
    );
  }

  bool get measurementPerformed => deviation != null;

  bool get isEligible =>
      matchingEvaluation?.isEligible == true && rejectionReasons.isEmpty;

  static List<String> _normalizeReasons(Iterable<String> reasons) {
    final uniqueReasons = LinkedHashSet<String>.from(reasons);
    return List<String>.unmodifiable(uniqueReasons);
  }
}
