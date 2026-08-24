enum RideStatus {
  matching,
  driverEnRoute,
  driverArrived,
  inProgress,
  completed,
  cancelled,
  expired;

  bool get isTerminal =>
      this == completed || this == cancelled || this == expired;

  bool get passengerCanCancel =>
      this == matching || this == driverEnRoute || this == driverArrived;
}

class RideLocation {
  const RideLocation({
    required this.latitude,
    required this.longitude,
    required this.addressLabel,
  });

  final double latitude;
  final double longitude;
  final String addressLabel;
}

class RideRoute {
  const RideRoute({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.encodedPolyline,
    this.computedAt,
  });

  final int distanceMeters;
  final int durationSeconds;
  final String encodedPolyline;
  final DateTime? computedAt;
}

class CanonicalRide {
  const CanonicalRide({
    required this.rideId,
    required this.status,
    required this.version,
    required this.pickup,
    required this.dropoff,
    required this.route,
    this.driverId,
    this.createdAt,
    this.updatedAt,
    this.acceptedAt,
    this.driverEnRouteAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.expiredAt,
    this.cancelledBy,
    this.terminalReason,
  });

  final String rideId;
  final RideStatus status;
  final int version;
  final String? driverId;
  final RideLocation pickup;
  final RideLocation dropoff;
  final RideRoute route;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? acceptedAt;
  final DateTime? driverEnRouteAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? expiredAt;
  final String? cancelledBy;
  final String? terminalReason;

  factory CanonicalRide.fromMap(Map<String, dynamic> map, {String? rideId}) {
    T require<T>(String key) {
      final value = map[key];
      if (value is! T) throw FormatException('Geçersiz yolculuk alanı: $key');
      return value;
    }

    final id = rideId ?? require<String>('rideId');
    final statusName = require<String>('status');
    final status = RideStatus.values.where((value) => value.name == statusName).firstOrNull;
    if (status == null) throw const FormatException('Bilinmeyen yolculuk durumu.');
    final versionValue = require<num>('version');
    if (versionValue != versionValue.roundToDouble() || versionValue < 1) {
      throw const FormatException('Geçersiz yolculuk sürümü.');
    }
    RideLocation location(String key) {
      final value = require<Map>(key);
      final data = Map<String, dynamic>.from(value);
      final latitude = data['latitude'];
      final longitude = data['longitude'];
      final label = data['addressLabel'];
      if (latitude is! num || longitude is! num || label is! String) {
        throw FormatException('Geçersiz yolculuk konumu: $key');
      }
      return RideLocation(latitude: latitude.toDouble(), longitude: longitude.toDouble(), addressLabel: label);
    }
    final routeData = Map<String, dynamic>.from(require<Map>('route'));
    final distance = routeData['distanceMeters'];
    final duration = routeData['durationSeconds'];
    final polyline = routeData['encodedPolyline'];
    if (distance is! num || duration is! num || polyline is! String) {
      throw const FormatException('Geçersiz yolculuk rotası.');
    }
    DateTime? time(String key) {
      final value = map[key];
      if (value == null) return null;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
      try {
        final dynamic converted = value;
        return converted.toDate() as DateTime;
      } catch (_) {
        throw FormatException('Geçersiz yolculuk zamanı: $key');
      }
    }
    return CanonicalRide(
      rideId: id,
      status: status,
      version: versionValue.toInt(),
      driverId: map['driverId'] as String?,
      pickup: location('pickup'),
      dropoff: location('dropoff'),
      route: RideRoute(
        distanceMeters: distance.toInt(),
        durationSeconds: duration.toInt(),
        encodedPolyline: polyline,
        computedAt: timeFrom(routeData['computedAtMillis'] ?? routeData['computedAt']),
      ),
      createdAt: time('createdAtMillis') ?? time('createdAt'),
      updatedAt: time('updatedAtMillis') ?? time('updatedAt'),
      acceptedAt: time('acceptedAtMillis') ?? time('acceptedAt'),
      driverEnRouteAt: time('driverEnRouteAtMillis') ?? time('driverEnRouteAt'),
      arrivedAt: time('arrivedAtMillis') ?? time('arrivedAt'),
      startedAt: time('startedAtMillis') ?? time('startedAt'),
      completedAt: time('completedAtMillis') ?? time('completedAt'),
      cancelledAt: time('cancelledAtMillis') ?? time('cancelledAt'),
      expiredAt: time('expiredAtMillis') ?? time('expiredAt'),
      cancelledBy: map['cancelledBy'] as String?,
      terminalReason: map['terminalReason'] as String?,
    );
  }

  static DateTime? timeFrom(Object? value) {
    if (value == null) return null;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    try {
      final dynamic converted = value;
      return converted.toDate() as DateTime;
    } catch (_) {
      throw const FormatException('Geçersiz yolculuk zamanı.');
    }
  }
}
