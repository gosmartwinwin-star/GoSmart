import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteService {
  Future<List<LatLng>> getRoute({
    required LatLng pickup,
    required LatLng destination,
  }) async {
    // Şimdilik boş liste.
    // Sonraki adımda gerçek Directions API bağlanacak.
    return [];
  }
}