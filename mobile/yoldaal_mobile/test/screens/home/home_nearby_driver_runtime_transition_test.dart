import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_live_tracking_gateway.dart';
import 'package:yoldaal_mobile/controllers/passenger_nearby_driver_controller.dart';
import 'package:yoldaal_mobile/controllers/passenger_ride_controller.dart';
import 'package:yoldaal_mobile/controllers/passenger_ride_live_tracking_controller.dart';
import 'package:yoldaal_mobile/domain/return_route/geo_coordinate.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/models/route_result_model.dart';
import 'package:yoldaal_mobile/screens/home/home_screen.dart';
import 'package:yoldaal_mobile/services/nearby_passenger_driver_service.dart';
import 'package:yoldaal_mobile/widgets/map/yoldaal_map.dart';
import 'package:yoldaal_mobile/application/ride/ride_chat_gateway.dart';

void main() {
  testWidgets(
    'matching approximate marker is replaced by assigned exact driver marker',
    (tester) async {
      final rideGateway = _MutableRideGateway(
        _ride(status: RideStatus.matching, version: 1),
      );

      final rideController = PassengerRideController(
        gateway: rideGateway,
        repository: rideGateway,
      );

      final nearbyController = PassengerNearbyDriverController(
        rideListenable: rideController,
        rideId: () => rideController.ride?.rideId,
        rideStatus: () => rideController.ride?.status,
        loader: () async => const <NearbyPassengerDriverProjection>[
          NearbyPassengerDriverProjection(
            latitude: 41.0080,
            longitude: 28.9780,
            updatedAtMillis: 1000,
          ),
        ],
        periodicTimerFactory: (_, callback) => _ManualTimer(callback),
      );

      final liveGateway = _LiveTrackingGateway();

      final liveTrackingController = PassengerRideLiveTrackingController(
        rideListenable: rideController,
        rideId: () => rideController.ride?.rideId,
        rideStatus: () => rideController.ride?.status,
        gateway: liveGateway,
        periodicTimerFactory: (_, callback) => _ManualTimer(callback),
      );

      addTearDown(rideGateway.close);
      addTearDown(rideController.dispose);
      addTearDown(nearbyController.dispose);
      addTearDown(liveTrackingController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            rideController: rideController,
            nearbyDriverController: nearbyController,
            liveTrackingController: liveTrackingController,
            chatGateway: const _NoopRideChatGateway(),
            authenticate: () async => true,
            routeLoader: ({required pickup, required destination}) async =>
                const RouteResultModel(
                  points: [],
                  distanceMeters: 0,
                  durationSeconds: 0,
                ),
          ),
        ),
      );

      await _pumpAsync(tester);

      var map = tester.widget<YoldaAlMap>(find.byType(YoldaAlMap));

      final matchingNearbyMarkers = map.markers
          .where((marker) => marker.markerId.value.startsWith('nearby_driver_'))
          .toList(growable: false);

      expect(matchingNearbyMarkers, hasLength(1));

      expect(matchingNearbyMarkers.single.position.latitude, 41.0080);

      expect(matchingNearbyMarkers.single.position.longitude, 28.9780);

      expect(
        map.markers.where(
          (marker) => marker.markerId.value == 'active_ride_driver',
        ),
        isEmpty,
      );

      expect(nearbyController.isActive, isTrue);
      expect(liveTrackingController.isActive, isFalse);

      rideGateway.emit(
        _ride(
          status: RideStatus.driverEnRoute,
          version: 2,
          driverId: 'internal-assigned-driver',
        ),
      );

      await _pumpAsync(tester);

      map = tester.widget<YoldaAlMap>(find.byType(YoldaAlMap));

      expect(
        map.markers.where(
          (marker) => marker.markerId.value.startsWith('nearby_driver_'),
        ),
        isEmpty,
      );

      final assignedMarkers = map.markers
          .where((marker) => marker.markerId.value == 'active_ride_driver')
          .toList(growable: false);

      expect(assignedMarkers, hasLength(1));

      expect(
        assignedMarkers.single.position.latitude,
        _LiveTrackingGateway.exactLatitude,
      );

      expect(
        assignedMarkers.single.position.longitude,
        _LiveTrackingGateway.exactLongitude,
      );

      expect(nearbyController.isActive, isFalse);
      expect(nearbyController.projections, isEmpty);
      expect(liveTrackingController.isActive, isTrue);
      expect(liveGateway.calls, 1);
    },
  );
}

Future<void> _pumpAsync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

CanonicalRide _ride({
  required RideStatus status,
  required int version,
  String? driverId,
}) {
  return CanonicalRide(
    rideId: 'runtime-nearby-transition',
    driverId: driverId,
    status: status,
    version: version,
    pickup: const RideLocation(
      latitude: 41.0082,
      longitude: 28.9784,
      addressLabel: 'Pickup',
    ),
    dropoff: const RideLocation(
      latitude: 41.0151,
      longitude: 28.9795,
      addressLabel: 'Dropoff',
    ),
    route: const RideRoute(
      distanceMeters: 1400,
      durationSeconds: 420,
      encodedPolyline: 'runtime_fixture_polyline',
    ),
  );
}

class _MutableRideGateway implements RideGateway, RideStreamRepository {
  _MutableRideGateway(this.activeRide);

  CanonicalRide activeRide;

  final StreamController<CanonicalRide> _rides =
      StreamController<CanonicalRide>.broadcast();

  void emit(CanonicalRide ride) {
    activeRide = ride;
    _rides.add(ride);
  }

  Future<void> close() => _rides.close();

  @override
  Future<CanonicalRide?> getMyActiveRide() async => activeRide;

  @override
  Future<CanonicalRide?> getMyActiveDriverRide() async => null;

  @override
  Stream<CanonicalRide> watchRide(String rideId) => _rides.stream;

  @override
  Future<CanonicalRide> getRide(String rideId) async => activeRide;

  @override
  Future<CanonicalRide> createRide({
    required String requestId,
    required RideLocation pickup,
    required RideLocation dropoff,
  }) => throw UnimplementedError('Unexpected createRide call.');

  @override
  Future<void> cancel({
    required String rideId,
    required String requestId,
    required int expectedVersion,
    required bool driver,
  }) async {}

  @override
  Future<void> markDriverArrived({
    required String rideId,
    required String requestId,
    required int expectedVersion,
  }) async {}

  @override
  Future<void> startRide({
    required String rideId,
    required String requestId,
    required int expectedVersion,
  }) async {}

  @override
  Future<void> completeRide({
    required String rideId,
    required String requestId,
    required int expectedVersion,
  }) async {}
}

class _LiveTrackingGateway implements RideLiveTrackingGateway {
  static const double exactLatitude = 41.009876;
  static const double exactLongitude = 28.979876;

  int calls = 0;

  @override
  Future<RideLiveTrackingSnapshot> getTracking({required String rideId}) async {
    calls++;

    final now = DateTime.now().millisecondsSinceEpoch;

    return RideLiveTrackingSnapshot(
      driverLocation: GeoCoordinate(
        latitude: exactLatitude,
        longitude: exactLongitude,
      ),
      updatedAtMillis: now,
      etaSeconds: 180,
      etaUpdatedAtMillis: now,
    );
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function(Timer timer) _callback;

  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) {
      return;
    }

    _tick++;
    _callback(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }
}

class _NoopRideChatGateway implements RideChatGateway {
  const _NoopRideChatGateway();

  @override
  Future<RideChatPage> listMessages({
    required String rideId,
    int pageSize = 50,
    RideChatCursor? cursor,
  }) async =>
      RideChatPage(
        rideId: rideId,
        messages: const <RideChatMessage>[],
        nextCursor: null,
      );

  @override
  Future<RideChatMessage> sendMessage({
    required String rideId,
    required String requestId,
    required String text,
  }) async {
    throw StateError('Unexpected ride chat send in legacy fixture.');
  }
}
