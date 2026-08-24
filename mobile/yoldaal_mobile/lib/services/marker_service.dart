import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/taxi_model.dart';

class MarkerService {
  MarkerService();

  Set<Marker> createTaxiMarkers({
    required List<TaxiModel> taxis,
    required void Function(TaxiModel taxi) onTap,
  }) {
    final Set<Marker> markers = {};

    for (final taxi in taxis) {
      markers.add(
        Marker(
          markerId: MarkerId("taxi_${taxi.id}"),

          position: LatLng(taxi.latitude, taxi.longitude),

          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow,
          ),

          infoWindow: InfoWindow(
            title: taxi.driverName,
            snippet: "${taxi.vehicleType} • ⭐ ${taxi.rating}",
          ),

          onTap: () {
            onTap(taxi);
          },
        ),
      );
    }

    return markers;
  }
}
