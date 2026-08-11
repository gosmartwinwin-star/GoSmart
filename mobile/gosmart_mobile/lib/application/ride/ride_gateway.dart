import '../../domain/ride/canonical_ride.dart';

class RideGatewayException implements Exception {
  const RideGatewayException(this.code, {this.reason});
  final String code;
  final String? reason;
}

abstract interface class RideGateway {
  Future<CanonicalRide?> getMyActiveRide();
  Future<CanonicalRide?> getMyActiveDriverRide();
  Future<CanonicalRide> createRide({
    required String requestId,
    required RideLocation pickup,
    required RideLocation dropoff,
  });
  Future<void> cancel({required String rideId, required String requestId, required int expectedVersion, required bool driver});
  Future<void> markDriverArrived({required String rideId, required String requestId, required int expectedVersion});
  Future<void> startRide({required String rideId, required String requestId, required int expectedVersion});
  Future<void> completeRide({required String rideId, required String requestId, required int expectedVersion});
}

abstract interface class RideStreamRepository {
  Stream<CanonicalRide> watchRide(String rideId);
  Future<CanonicalRide> getRide(String rideId);
}
