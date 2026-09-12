import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/widgets/ride/canonical_ride_card.dart';
import 'package:yoldaal_mobile/widgets/ride/planned_ride_route_map.dart';

const pickup = RideLocation(
  latitude: 41.0256,
  longitude: 28.9741,
  addressLabel: 'Alış noktası',
);

const dropoff = RideLocation(
  latitude: 41.0356,
  longitude: 28.9841,
  addressLabel: 'Varış noktası',
);

CanonicalRide ride(
  RideStatus status, {
  String encodedPolyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
}) =>
    CanonicalRide(
      rideId: 'ride-map-1',
      status: status,
      version: 1,
      pickup: pickup,
      dropoff: dropoff,
      route: RideRoute(
        distanceMeters: 1800,
        durationSeconds: 420,
        encodedPolyline: encodedPolyline,
      ),
    );

Future<void> showMap(
  WidgetTester tester,
  CanonicalRide value,
) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannedRideRouteMap(ride: value),
        ),
      ),
    );

Future<void> showCard(
  WidgetTester tester,
  RideStatus status, {
  required bool driver,
}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanonicalRideCard(
            ride: ride(status),
            driver: driver,
            loading: false,
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'planned ride map uses canonical route and endpoints without live location',
    (tester) async {
      await showMap(
        tester,
        ride(RideStatus.inProgress),
      );

      final map = tester.widget<GoogleMap>(
        find.byType(GoogleMap),
      );

      expect(map.myLocationEnabled, isFalse);
      expect(map.myLocationButtonEnabled, isFalse);

      final pickupMarker = map.markers.singleWhere(
        (marker) => marker.markerId.value == 'ride_pickup',
      );
      final dropoffMarker = map.markers.singleWhere(
        (marker) => marker.markerId.value == 'ride_dropoff',
      );

      expect(
        pickupMarker.position,
        const LatLng(41.0256, 28.9741),
      );
      expect(
        dropoffMarker.position,
        const LatLng(41.0356, 28.9841),
      );

      final routeLine = map.polylines.singleWhere(
        (polyline) =>
            polyline.polylineId.value == 'planned_ride_route',
      );

      expect(routeLine.points.length, greaterThanOrEqualTo(2));
      expect(
        find.text('Planlanan yolculuk rotası'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'malformed canonical polyline fails presentation closed',
    (tester) async {
      await showMap(
        tester,
        ride(
          RideStatus.inProgress,
          encodedPolyline: 'x',
        ),
      );

      expect(find.byType(GoogleMap), findsNothing);
      expect(
        find.byKey(
          const ValueKey('planned-ride-route-map-invalid'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shared ride card exposes planned route to both actors only post-match active',
    (tester) async {
      for (final driver in <bool>[false, true]) {
        await showCard(
          tester,
          RideStatus.driverEnRoute,
          driver: driver,
        );

        expect(
          find.byType(PlannedRideRouteMap),
          findsOneWidget,
        );

        await showCard(
          tester,
          RideStatus.driverArrived,
          driver: driver,
        );

        expect(
          find.byType(PlannedRideRouteMap),
          findsOneWidget,
        );

        await showCard(
          tester,
          RideStatus.inProgress,
          driver: driver,
        );

        expect(
          find.byType(PlannedRideRouteMap),
          findsOneWidget,
        );
      }

      await showCard(
        tester,
        RideStatus.matching,
        driver: false,
      );

      expect(
        find.byType(PlannedRideRouteMap),
        findsNothing,
      );

      await showCard(
        tester,
        RideStatus.completed,
        driver: false,
      );

      expect(
        find.byType(PlannedRideRouteMap),
        findsNothing,
      );
    },
  );
}
