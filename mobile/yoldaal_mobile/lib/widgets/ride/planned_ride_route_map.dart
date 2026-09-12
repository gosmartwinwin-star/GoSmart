import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../domain/ride/canonical_ride.dart';
import '../../infrastructure/polyline/geo_polyline_decoder.dart';

class PlannedRideRouteMap extends StatelessWidget {
  const PlannedRideRouteMap({
    super.key,
    required this.ride,
  });

  final CanonicalRide ride;

  @override
  Widget build(BuildContext context) {
    late final List<LatLng> routePoints;

    try {
      routePoints = GeoPolylineDecoder.decode(
        ride.route.encodedPolyline,
      )
          .map(
            (point) => LatLng(
              point.latitude,
              point.longitude,
            ),
          )
          .toList(growable: false);
    } on FormatException {
      return const SizedBox.shrink(
        key: ValueKey('planned-ride-route-map-invalid'),
      );
    }

    final pickup = LatLng(
      ride.pickup.latitude,
      ride.pickup.longitude,
    );
    final dropoff = LatLng(
      ride.dropoff.latitude,
      ride.dropoff.longitude,
    );

    final boundsPoints = <LatLng>[
      ...routePoints,
      pickup,
      dropoff,
    ];

    return Column(
      key: const ValueKey('planned-ride-route-map'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Planlanan yolculuk rotası',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: pickup,
                zoom: 12,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('ride_pickup'),
                  position: pickup,
                ),
                Marker(
                  markerId: const MarkerId('ride_dropoff'),
                  position: dropoff,
                ),
              },
              polylines: {
                Polyline(
                  polylineId: const PolylineId('planned_ride_route'),
                  points: routePoints,
                  color: Theme.of(context).colorScheme.primary,
                  width: 6,
                ),
              },
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onMapCreated: (controller) async {
                var minLat = boundsPoints.first.latitude;
                var maxLat = minLat;
                var minLng = boundsPoints.first.longitude;
                var maxLng = minLng;

                for (final point in boundsPoints.skip(1)) {
                  minLat = math.min(minLat, point.latitude);
                  maxLat = math.max(maxLat, point.latitude);
                  minLng = math.min(minLng, point.longitude);
                  maxLng = math.max(maxLng, point.longitude);
                }

                await controller.animateCamera(
                  CameraUpdate.newLatLngBounds(
                    LatLngBounds(
                      southwest: LatLng(minLat, minLng),
                      northeast: LatLng(maxLat, maxLng),
                    ),
                    48,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
