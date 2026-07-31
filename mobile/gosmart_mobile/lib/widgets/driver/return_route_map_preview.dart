import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../application/return_route/published_return_route.dart';

class ReturnRouteMapPreview extends StatelessWidget {
  final PublishedReturnRoute published;

  const ReturnRouteMapPreview({super.key, required this.published});

  @override
  Widget build(BuildContext context) {
    final points = published.route.routePoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    return SizedBox(
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: points.first, zoom: 12),
          markers: {
            Marker(markerId: const MarkerId('origin'), position: points.first),
            Marker(
              markerId: const MarkerId('destination'),
              position: points.last,
            ),
          },
          polylines: {
            Polyline(
              polylineId: const PolylineId('return_route'),
              points: points,
              color: Theme.of(context).colorScheme.primary,
              width: 6,
            ),
          },
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          onMapCreated: (controller) async {
            var minLat = points.first.latitude;
            var maxLat = minLat;
            var minLng = points.first.longitude;
            var maxLng = minLng;
            for (final point in points.skip(1)) {
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
    );
  }
}
