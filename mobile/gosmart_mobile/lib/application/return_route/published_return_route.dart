import '../../domain/return_route/driver_return_route.dart';
import '../../domain/return_route/driver_return_route_status.dart';

class PublishedReturnRoute {
  final DriverReturnRoute route;
  final String encodedPolyline;

  PublishedReturnRoute({required this.route, required String encodedPolyline})
    : encodedPolyline = encodedPolyline {
    if (encodedPolyline.trim().isEmpty) {
      throw ArgumentError.value(
        encodedPolyline,
        'encodedPolyline',
        'Boş olamaz.',
      );
    }
    if (route.status != DriverReturnRouteStatus.active ||
        !route.hasCalculatedRoute ||
        route.activatedAt == null ||
        route.expiresAt == null ||
        !route.expiresAt!.isAfter(route.activatedAt!) ||
        route.routePoints.length < 2) {
      throw ArgumentError('Geçerli ve aktif bir dönüş rotası gereklidir.');
    }
  }

  String get routeId => route.id;
  String get driverId => route.driverId;
  DateTime get activatedAt => route.activatedAt!;
  DateTime get expiresAt => route.expiresAt!;
  int get distanceMeters => route.routeDistanceMeters!;
  int get durationSeconds => route.routeDurationSeconds!;
  Duration get validityDuration => expiresAt.difference(activatedAt);
}
