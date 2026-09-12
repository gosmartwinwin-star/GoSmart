class RideRatingStatus {
  const RideRatingStatus({
    required this.rideId,
    required this.hasSubmitted,
    this.rating,
    this.submittedAt,
  });

  final String rideId;
  final bool hasSubmitted;
  final int? rating;
  final DateTime? submittedAt;
}

abstract interface class RideRatingGateway {
  Future<RideRatingStatus> getMyRatingStatus({
    required String rideId,
  });

  Future<RideRatingStatus> submitRating({
    required String rideId,
    required int rating,
    required String requestId,
  });
}
