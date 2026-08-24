import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/address_model.dart';

class RouteMarkerService {
  Set<Marker> createRouteMarkers({
    AddressModel? pickup,
    AddressModel? destination,
  }) {
    final markers = <Marker>{};

    if (pickup != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("pickup"),
          position: LatLng(
            pickup.latitude,
            pickup.longitude,
          ),
          infoWindow: InfoWindow(
            title: pickup.title,
          ),
        ),
      );
    }

    if (destination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("destination"),
          position: LatLng(
            destination.latitude,
            destination.longitude,
          ),
          infoWindow: InfoWindow(
            title: destination.title,
          ),
        ),
      );
    }

    return markers;
  }
}
