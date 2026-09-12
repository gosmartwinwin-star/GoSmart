const rideSupportCategories = <String>[
  'safety',
  'behavior',
  'fare',
  'route',
  'pickup',
  'no-show',
  'cancel',
  'vehicle',
  'technical',
  'lost-item',
];

class RideSupportCaseResult {
  const RideSupportCaseResult({
    required this.rideId,
    required this.caseId,
    required this.category,
    required this.createdAt,
  });

  final String rideId;
  final String caseId;
  final String category;
  final DateTime createdAt;
}

abstract interface class RideSupportGateway {
  Future<RideSupportCaseResult> createCase({
    required String rideId,
    required String category,
    required String requestId,
  });
}
abstract interface class RideActiveSupportGateway {
  Future<RideSupportCaseResult> createActiveCase({
    required String rideId,
    required String category,
    required String requestId,
  });
}
