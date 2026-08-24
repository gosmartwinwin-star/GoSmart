import 'dart:math' as math;

import 'geo_coordinate.dart';

abstract final class GeoDistance {
  static const double _earthRadiusMeters = 6371000;

  /// Yalnızca geometrik yakınlık için yaklaşık büyük daire mesafesidir.
  /// Sürüş mesafesi veya rota sapması değildir.
  static double betweenMeters(GeoCoordinate first, GeoCoordinate second) {
    if (first == second) return 0;

    final firstLatitude = _toRadians(first.latitude);
    final secondLatitude = _toRadians(second.latitude);
    final latitudeDifference = secondLatitude - firstLatitude;
    final longitudeDifference = _toRadians(second.longitude - first.longitude);

    final latitudeSin = math.sin(latitudeDifference / 2);
    final longitudeSin = math.sin(longitudeDifference / 2);
    final haversine =
        latitudeSin * latitudeSin +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            longitudeSin *
            longitudeSin;
    final normalizedHaversine = haversine.clamp(0.0, 1.0);
    final centralAngle =
        2 *
        math.atan2(
          math.sqrt(normalizedHaversine),
          math.sqrt(1 - normalizedHaversine),
        );

    return _earthRadiusMeters * centralAngle;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
