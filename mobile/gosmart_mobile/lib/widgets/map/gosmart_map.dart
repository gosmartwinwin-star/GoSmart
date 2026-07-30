import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GoSmartMap extends StatelessWidget {
  final CameraPosition initialPosition;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Function(GoogleMapController) onMapCreated;
  final Function(LatLng)? onTap;

  const GoSmartMap({
    super.key,
    required this.initialPosition,
    required this.markers,
    this.polylines = const {},
    required this.onMapCreated,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: initialPosition,

      markers: markers,

      polylines: polylines,

      myLocationEnabled: true,
      myLocationButtonEnabled: true,

      zoomControlsEnabled: false,

      compassEnabled: true,

      mapToolbarEnabled: false,

      buildingsEnabled: true,

      trafficEnabled: false,

      onTap: onTap,

      onMapCreated: onMapCreated,
    );
  }
}