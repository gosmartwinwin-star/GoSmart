import '../../domain/return_route/geo_coordinate.dart';

class DriverLivePresencePublishResult {
  final int updatedAtMillis;

  const DriverLivePresencePublishResult({required this.updatedAtMillis});
}

class DriverLivePresencePublishException implements Exception {
  final String code;
  final String? reason;

  const DriverLivePresencePublishException({
    required this.code,
    this.reason,
  });
}

abstract interface class DriverLivePresenceGateway {
  Future<DriverLivePresencePublishResult> publish({
    required GeoCoordinate location,
  });
}
