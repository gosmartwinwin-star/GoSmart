import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/controllers/passenger_ride_controller.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/models/route_result_model.dart';
import 'package:gosmart_mobile/screens/home/home_screen.dart';

void main() {
  testWidgets('Taksi Ara route sonrası tek canonical ride oluşturur', (
    tester,
  ) async {
    final gateway = _FakeRideGateway();
    final controller = PassengerRideController(
      gateway: gateway,
      repository: gateway,
      requestIdGenerator: () => 'request-1',
    );
    final routeCompleter = Completer<RouteResultModel>();
    var routeCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          rideController: controller,
          authenticate: () async => true,
          routeLoader: ({required pickup, required destination}) {
            routeCalls++;
            return routeCompleter.future;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Nereden alınacaksınız?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GoSmart Merkez'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nereye gidiyorsunuz?'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Galata Kulesi'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Galata Kulesi'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Taksi Ara'));
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(routeCalls, 1);
    expect(gateway.createCalls, 0);

    routeCompleter.complete(
      const RouteResultModel(
        points: [LatLng(41.0105, 28.9717), LatLng(41.0256, 28.9744)],
        distanceMeters: 1800,
        durationSeconds: 420,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(gateway.createCalls, 1);
    expect(gateway.pickup?.latitude, 41.0105);
    expect(gateway.pickup?.longitude, 28.9717);
    expect(gateway.pickup?.addressLabel, 'GoSmart Merkez');
    expect(gateway.dropoff?.latitude, 41.0256);
    expect(gateway.dropoff?.longitude, 28.9744);
    expect(gateway.dropoff?.addressLabel, 'Galata Kulesi');

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(routeCalls, 1);
    expect(gateway.createCalls, 1);

    gateway.createCompleter.complete(gateway.createdRide);
    await tester.pumpAndSettle();

    expect(gateway.createdRide.driverId, isNull);
    expect(find.text('Sürücü aranıyor'), findsOneWidget);
    expect(find.text('Taksi Ara'), findsNothing);

    controller.dispose();
  });
}

class _FakeRideGateway implements RideGateway, RideStreamRepository {
  int createCalls = 0;
  RideLocation? pickup;
  RideLocation? dropoff;
  final Completer<CanonicalRide> createCompleter =
      Completer<CanonicalRide>();

  late final CanonicalRide createdRide = CanonicalRide(
    rideId: 'ride-1',
    status: RideStatus.matching,
    version: 1,
    pickup: pickup!,
    dropoff: dropoff!,
    route: const RideRoute(
      distanceMeters: 1800,
      durationSeconds: 420,
      encodedPolyline: 'encoded',
    ),
  );

  @override
  Future<CanonicalRide> createRide({
    required String requestId,
    required RideLocation pickup,
    required RideLocation dropoff,
  }) {
    createCalls++;
    this.pickup = pickup;
    this.dropoff = dropoff;
    return createCompleter.future;
  }

  @override
  Future<CanonicalRide?> getMyActiveRide() async => null;

  @override
  Stream<CanonicalRide> watchRide(String rideId) => const Stream.empty();

  @override
  Future<CanonicalRide> getRide(String rideId) async => createdRide;

  @override
  Future<CanonicalRide?> getMyActiveDriverRide() async => null;

  @override
  Future<void> cancel({
    required String rideId,
    required String requestId,
    required int expectedVersion,
    required bool driver,
  }) async {}

  @override
  Future<void> completeRide({
    required String rideId,
    required String requestId,
    required int expectedVersion,
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
}
