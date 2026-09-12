import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/screens/home/home_screen.dart').readAsStringSync();
  });

  test(
    'HomeScreen wires injectable nearby controller and owned production service',
    () {
      expect(
        source,
        contains(
          "import '../../controllers/passenger_nearby_driver_controller.dart';",
        ),
      );

      expect(
        source,
        contains(
          "import '../../services/nearby_passenger_driver_service.dart';",
        ),
      );

      expect(source, contains('this.nearbyDriverController,'));

      expect(
        source,
        contains(
          'final PassengerNearbyDriverController? nearbyDriverController;',
        ),
      );

      expect(source, contains('bool _ownsNearbyDriverController = false;'));

      expect(
        source,
        contains(
          'final injectedNearbyDriverController = widget.nearbyDriverController;',
        ),
      );

      expect(
        source,
        contains('final nearbyDriverService = NearbyPassengerDriverService();'),
      );

      expect(source, contains('rideListenable: rideController,'));

      expect(source, contains('rideId: () => rideController.ride?.rideId,'));

      expect(
        source,
        contains('rideStatus: () => rideController.ride?.status,'),
      );

      expect(source, contains('loader: nearbyDriverService.load,'));
    },
  );

  test(
    'HomeScreen starts listens and disposes only owned nearby controller',
    () {
      expect(
        source,
        contains('nearbyDriverController?.addListener(_refreshNearbyDrivers);'),
      );

      expect(source, contains('nearbyDriverController?.start();'));

      expect(
        source,
        contains(
          'nearbyDriverController?.removeListener(_refreshNearbyDrivers);',
        ),
      );

      expect(source, contains('if (_ownsNearbyDriverController) {'));

      expect(source, contains('nearbyDriverController?.dispose();'));
    },
  );

  test(
    'HomeScreen renders only public approximate coordinates with local marker identity',
    () {
      final start = source.indexOf('void _applyNearbyDriverMarkers()');

      final end = source.indexOf('void _applyLiveDriverMarker()');

      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));

      final method = source.substring(start, end);

      expect(
        method,
        contains("marker.markerId.value.startsWith('nearby_driver_')"),
      );

      expect(method, contains("MarkerId('nearby_driver_\$index')"));

      expect(
        method,
        contains('LatLng(projection.latitude, projection.longitude)'),
      );

      expect(method, contains("InfoWindow(title: 'Yakındaki sürücü')"));

      expect(method, isNot(contains('projection.driverId')));
      expect(method, isNot(contains('projection.distance')));
      expect(method, isNot(contains('projection.measurement')));
    },
  );

  test('approximate markers are applied before assigned exact marker', () {
    final start = source.indexOf('void _refreshMarkers()');

    final end = source.indexOf('void _refreshLiveTracking()');

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final refreshMethod = source.substring(start, end);

    final nearbyIndex = refreshMethod.indexOf('_applyNearbyDriverMarkers();');

    final exactIndex = refreshMethod.indexOf('_applyLiveDriverMarker();');

    expect(nearbyIndex, greaterThanOrEqualTo(0));
    expect(exactIndex, greaterThan(nearbyIndex));

    expect(source, contains("markerId: const MarkerId('active_ride_driver')"));
  });
}
