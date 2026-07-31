import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteResultModel {
  final List<LatLng> points;
  final int distanceMeters;
  final int durationSeconds;

  const RouteResultModel({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}
