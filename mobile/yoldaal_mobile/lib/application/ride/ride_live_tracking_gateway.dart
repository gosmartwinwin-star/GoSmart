import '../../domain/return_route/geo_coordinate.dart';

class RideLiveTrackingSnapshot {
  const RideLiveTrackingSnapshot({
    required this.driverLocation,
    required this.updatedAtMillis,
    required this.etaSeconds,
    required this.etaUpdatedAtMillis,
  });

  final GeoCoordinate? driverLocation;
  final int? updatedAtMillis;
  final int? etaSeconds;
  final int? etaUpdatedAtMillis;
}

abstract interface class RideLiveTrackingGateway {
  Future<RideLiveTrackingSnapshot> getTracking({
    required String rideId,
  });
}

class RideLiveTrackingException implements Exception {
  const RideLiveTrackingException({
    required this.code,
    this.reason,
  });

  final String code;
  final String? reason;

  @override
  String toString() =>
      'RideLiveTrackingException(code: $code, reason: $reason)';
}
