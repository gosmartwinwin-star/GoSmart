import 'geo_coordinate.dart';

class RouteAnchorResult {
  final int pickupRouteIndex;
  final int dropoffRouteIndex;
  final GeoCoordinate pickupAnchor;
  final GeoCoordinate dropoffAnchor;
  final double pickupAnchorProximityMeters;
  final double dropoffAnchorProximityMeters;

  RouteAnchorResult({
    required int pickupRouteIndex,
    required int dropoffRouteIndex,
    required this.pickupAnchor,
    required this.dropoffAnchor,
    required double pickupAnchorProximityMeters,
    required double dropoffAnchorProximityMeters,
  }) : pickupRouteIndex = _requireNonNegativeIndex(
         pickupRouteIndex,
         'pickupRouteIndex',
       ),
       dropoffRouteIndex = _requireNonNegativeIndex(
         dropoffRouteIndex,
         'dropoffRouteIndex',
       ),
       pickupAnchorProximityMeters = _requireValidProximity(
         pickupAnchorProximityMeters,
         'pickupAnchorProximityMeters',
       ),
       dropoffAnchorProximityMeters = _requireValidProximity(
         dropoffAnchorProximityMeters,
         'dropoffAnchorProximityMeters',
       );

  bool get directionCompatible => pickupRouteIndex < dropoffRouteIndex;

  double get totalAnchorProximityMeters =>
      pickupAnchorProximityMeters + dropoffAnchorProximityMeters;

  static int _requireNonNegativeIndex(int value, String name) {
    if (value < 0) {
      throw ArgumentError.value(value, name, 'Negatif olamaz.');
    }

    return value;
  }

  static double _requireValidProximity(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        name,
        'Sonlu ve negatif olmayan bir değer olmalıdır.',
      );
    }

    return value;
  }
}
