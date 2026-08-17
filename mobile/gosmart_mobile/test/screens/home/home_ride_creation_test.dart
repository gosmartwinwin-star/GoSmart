import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/location/location_access_gateway.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/controllers/passenger_ride_controller.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/models/route_result_model.dart';
import 'package:gosmart_mobile/screens/home/home_screen.dart';
import 'package:gosmart_mobile/widgets/map/gosmart_map.dart';

void main() {
  testWidgets('home denied forever shows app settings', (tester) async {
    final rideGateway = _FakeRideGateway();
    final rideController = PassengerRideController(
      gateway: rideGateway,
      repository: rideGateway,
    );
    final location = _HomeLocationGateway(
      LocationAccessIssue.permissionDeniedForever,
    );

    addTearDown(rideController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          rideController: rideController,
          locationAccess: location,
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
    await tester.pump();

    final map = tester.widget<GoSmartMap>(find.byType(GoSmartMap));

    await map.onMapCreated(_FakeGoogleMapController());
    await tester.pump();

    expect(location.currentCalls, 1);
    expect(
      find.byKey(const ValueKey('home-location-access-banner')),
      findsOneWidget,
    );
    expect(find.text('Uygulama Ayarlar\u0131'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);

    await tester.tap(find.text('Uygulama Ayarlar\u0131'));
    await tester.pump();

    expect(location.appSettingsCalls, 1);
    expect(location.locationSettingsCalls, 0);
  });

  testWidgets('home service disabled shows location settings', (tester) async {
    final rideGateway = _FakeRideGateway();
    final rideController = PassengerRideController(
      gateway: rideGateway,
      repository: rideGateway,
    );
    final location = _HomeLocationGateway(LocationAccessIssue.serviceDisabled);

    addTearDown(rideController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          rideController: rideController,
          locationAccess: location,
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
    await tester.pump();

    final map = tester.widget<GoSmartMap>(find.byType(GoSmartMap));

    await map.onMapCreated(_FakeGoogleMapController());
    await tester.pump();

    expect(location.currentCalls, 1);
    expect(find.text('Konum Ayarlar\u0131'), findsOneWidget);

    await tester.tap(find.text('Konum Ayarlar\u0131'));
    await tester.pump();

    expect(location.locationSettingsCalls, 1);
    expect(location.appSettingsCalls, 0);
  });

  testWidgets('home denied retry requests location again', (tester) async {
    final rideGateway = _FakeRideGateway();
    final rideController = PassengerRideController(
      gateway: rideGateway,
      repository: rideGateway,
    );
    final location = _HomeLocationGateway(LocationAccessIssue.permissionDenied);

    addTearDown(rideController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          rideController: rideController,
          locationAccess: location,
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
    await tester.pump();

    final map = tester.widget<GoSmartMap>(find.byType(GoSmartMap));

    await map.onMapCreated(_FakeGoogleMapController());
    await tester.pump();

    expect(location.currentCalls, 1);
    expect(find.text('Tekrar Dene'), findsOneWidget);

    await tester.tap(find.text('Tekrar Dene'));
    await tester.pump();
    await tester.pump();

    expect(location.currentCalls, 2);
    expect(
      find.byKey(const ValueKey('home-location-access-banner')),
      findsOneWidget,
    );
  });
  testWidgets('Profil dokunuşu gerçek hesap yüzeyini açar', (tester) async {
    final gateway = _FakeRideGateway();
    final controller = PassengerRideController(
      gateway: gateway,
      repository: gateway,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          rideController: controller,
          authenticate: () async => true,
          routeLoader: ({required pickup, required destination}) async =>
              const RouteResultModel(
                points: [],
                distanceMeters: 0,
                durationSeconds: 0,
              ),
          profileScreenBuilder: (_) =>
              const Scaffold(body: Text('Hesap yüzeyi')),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();

    expect(find.text('Hesap yüzeyi'), findsOneWidget);
    controller.dispose();
  });

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
  final Completer<CanonicalRide> createCompleter = Completer<CanonicalRide>();

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

class _HomeLocationGateway implements LocationAccessGateway {
  _HomeLocationGateway(this.issue);

  final LocationAccessIssue issue;
  int currentCalls = 0;
  int appSettingsCalls = 0;
  int locationSettingsCalls = 0;

  @override
  Future<LocationAccessResult> currentLocation() async {
    currentCalls++;
    return LocationAccessResult.failed(issue);
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCalls++;
    return true;
  }
}

class _FakeGoogleMapController implements GoogleMapController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
