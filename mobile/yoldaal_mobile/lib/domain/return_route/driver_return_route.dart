import 'driver_return_route_status.dart';
import 'geo_coordinate.dart';

class DriverReturnRoute {
  final String id;
  final String driverId;
  final GeoCoordinate origin;
  final GeoCoordinate destination;
  final DriverReturnRouteStatus status;
  final DateTime createdAt;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final int? routeDistanceMeters;
  final int? routeDurationSeconds;
  final List<GeoCoordinate> routePoints;

  const DriverReturnRoute._({
    required this.id,
    required this.driverId,
    required this.origin,
    required this.destination,
    required this.status,
    required this.createdAt,
    required this.activatedAt,
    required this.expiresAt,
    required this.routeDistanceMeters,
    required this.routeDurationSeconds,
    required this.routePoints,
  });

  factory DriverReturnRoute({
    required String id,
    required String driverId,
    required GeoCoordinate origin,
    required GeoCoordinate destination,
    required DriverReturnRouteStatus status,
    required DateTime createdAt,
    DateTime? activatedAt,
    DateTime? expiresAt,
    int? routeDistanceMeters,
    int? routeDurationSeconds,
    List<GeoCoordinate> routePoints = const [],
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Boş olamaz.');
    }
    if (driverId.trim().isEmpty) {
      throw ArgumentError.value(driverId, 'driverId', 'Boş olamaz.');
    }
    if (origin == destination) {
      throw ArgumentError(
        'Origin ve destination aynı koordinat olamaz.',
        'destination',
      );
    }
    if (routeDistanceMeters != null && routeDistanceMeters <= 0) {
      throw ArgumentError.value(
        routeDistanceMeters,
        'routeDistanceMeters',
        'Sıfırdan büyük olmalıdır.',
      );
    }
    if (routeDurationSeconds != null && routeDurationSeconds <= 0) {
      throw ArgumentError.value(
        routeDurationSeconds,
        'routeDurationSeconds',
        'Sıfırdan büyük olmalıdır.',
      );
    }
    if (routePoints.length == 1) {
      throw ArgumentError.value(
        routePoints.length,
        'routePoints',
        'Boş veya en az iki noktalı olmalıdır.',
      );
    }
    if (activatedAt != null && createdAt.isAfter(activatedAt)) {
      throw ArgumentError(
        'createdAt, activatedAt değerinden sonra olamaz.',
        'createdAt',
      );
    }
    if (activatedAt != null &&
        expiresAt != null &&
        !expiresAt.isAfter(activatedAt)) {
      throw ArgumentError(
        'expiresAt, activatedAt değerinden sonra olmalıdır.',
        'expiresAt',
      );
    }

    if (status == DriverReturnRouteStatus.active) {
      if (activatedAt == null) {
        throw ArgumentError(
          'Aktif dönüş rotasında activatedAt zorunludur.',
          'activatedAt',
        );
      }
      if (expiresAt == null) {
        throw ArgumentError(
          'Aktif dönüş rotasında expiresAt zorunludur.',
          'expiresAt',
        );
      }
      if (routeDistanceMeters == null ||
          routeDurationSeconds == null ||
          routePoints.length < 2) {
        throw ArgumentError(
          'Aktif dönüş rotasında hesaplanmış rota zorunludur.',
          'routePoints',
        );
      }
    }

    return DriverReturnRoute._(
      id: id,
      driverId: driverId,
      origin: origin,
      destination: destination,
      status: status,
      createdAt: createdAt,
      activatedAt: activatedAt,
      expiresAt: expiresAt,
      routeDistanceMeters: routeDistanceMeters,
      routeDurationSeconds: routeDurationSeconds,
      routePoints: List<GeoCoordinate>.unmodifiable(routePoints),
    );
  }

  bool get hasCalculatedRoute =>
      routeDistanceMeters != null &&
      routeDurationSeconds != null &&
      routePoints.length >= 2;

  int get routePointCount => routePoints.length;

  bool isActiveAt(DateTime now) {
    final activation = activatedAt;
    final expiration = expiresAt;

    return status == DriverReturnRouteStatus.active &&
        activation != null &&
        expiration != null &&
        !now.isBefore(activation) &&
        now.isBefore(expiration);
  }

  Duration remainingAt(DateTime now) {
    if (!isActiveAt(now)) return Duration.zero;

    final remaining = expiresAt!.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  GeoCoordinate pointAt(int index) {
    if (index < 0 || index >= routePoints.length) {
      throw RangeError.index(index, routePoints, 'index');
    }

    return routePoints[index];
  }
}
