import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GoSmartMap extends StatelessWidget {
  const GoSmartMap({
    super.key,
    required this.initialPosition,
    required this.markers,
    required this.onMapCreated,
    required this.onTap,
  });

  final CameraPosition initialPosition;

  final Set<Marker> markers;

  final ValueChanged<GoogleMapController> onMapCreated;

  final ValueChanged<LatLng> onTap;

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: initialPosition,

      markers: markers,

      myLocationEnabled: true,

      myLocationButtonEnabled: true,

      zoomControlsEnabled: false,

      compassEnabled: true,

      buildingsEnabled: true,

      trafficEnabled: false,

      mapToolbarEnabled: false,

      onTap: onTap,

      onMapCreated: onMapCreated,
    );
  }
}