import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_pass_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_profile_repository.dart';
import 'package:gosmart_mobile/application/location/location_access_gateway.dart';
import 'package:gosmart_mobile/application/return_route/publish_return_route_gateway.dart';
import 'package:gosmart_mobile/application/return_route/published_return_route.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/application/ride/ride_match_offer_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_center_controller.dart';
import 'package:gosmart_mobile/controllers/driver_ride_controller.dart';
import 'package:gosmart_mobile/controllers/driver_ride_match_offer_controller.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/domain/ride/ride_match_offer.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';
import 'package:gosmart_mobile/screens/driver/driver_center_screen.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 16);

  testWidgets('active return route discovers offers exactly once', (
    tester,
  ) async {
    final center = _center(now);
    center.publishedRoute = _published(now);

    final rideGateway = _RideGateway();

    final rides = DriverRideController(
      gateway: rideGateway,
      repository: rideGateway,
    );

    addTearDown(rides.dispose);

    final offerGateway = _OfferGateway()
      ..loaded = [_offer(now.add(const Duration(minutes: 2)))];

    final matches = DriverRideMatchOfferController(
      gateway: offerGateway,
      requestIdGenerator: () => 'request_123456789',
      now: () => now,
    );

    addTearDown(matches.dispose);
    addTearDown(center.dispose);

    await _pumpCenter(tester, center: center, rides: rides, matches: matches);

    expect(offerGateway.loadCalls, 1);

    expect(
      find.byKey(const ValueKey('ride-match-offer-panel')),
      findsOneWidget,
    );

    expect(find.text('Alış: Kadıköy'), findsOneWidget);

    expect(find.text('Varış: Bostancı'), findsOneWidget);
  });

  testWidgets(
    'route replacement refreshes discovery without duplicate same-route load',
    (tester) async {
      final center = _center(now);
      center.publishedRoute = _published(now);

      final rideGateway = _RideGateway();

      final rides = DriverRideController(
        gateway: rideGateway,
        repository: rideGateway,
      );

      addTearDown(rides.dispose);

      final offerGateway = _OfferGateway()
        ..loaded = [_offer(now.add(const Duration(minutes: 2)))];

      final matches = DriverRideMatchOfferController(
        gateway: offerGateway,
        requestIdGenerator: () => 'request_123456789',
        now: () => now,
      );

      addTearDown(matches.dispose);
      addTearDown(center.dispose);

      await _pumpCenter(tester, center: center, rides: rides, matches: matches);

      expect(offerGateway.loadCalls, 1);

      center.selectValidity(1800);
      await tester.pumpAndSettle();

      expect(
        offerGateway.loadCalls,
        1,
        reason: 'same return route must not duplicate discovery',
      );

      center.publishedRoute = _published(now, routeId: 'route-2');
      center.selectValidity(3600);

      await tester.pumpAndSettle();

      expect(
        offerGateway.loadCalls,
        2,
        reason: 'new return route must trigger fresh discovery',
      );

      center.publishedRoute = null;
      center.selectValidity(1800);

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ride-match-offer-panel')),
        findsNothing,
      );

      center.publishedRoute = _published(now, routeId: 'route-2');
      center.selectValidity(3600);

      await tester.pumpAndSettle();

      expect(
        offerGateway.loadCalls,
        3,
        reason: 'route removal must reset the discovery marker',
      );
    },
  );
  testWidgets('active canonical ride suppresses discovery and offer panel', (
    tester,
  ) async {
    final center = _center(now);
    center.publishedRoute = _published(now);

    final rideGateway = _RideGateway()..activeRide = fixtureRide;

    final rides = DriverRideController(
      gateway: rideGateway,
      repository: rideGateway,
    );

    addTearDown(rides.dispose);

    final offerGateway = _OfferGateway()
      ..loaded = [_offer(now.add(const Duration(minutes: 2)))];

    final matches = DriverRideMatchOfferController(
      gateway: offerGateway,
      requestIdGenerator: () => 'request_123456789',
      now: () => now,
    );

    addTearDown(matches.dispose);
    addTearDown(center.dispose);

    await _pumpCenter(tester, center: center, rides: rides, matches: matches);

    expect(offerGateway.loadCalls, 0);

    expect(find.text('Yolcunun konumuna gidiliyor'), findsOneWidget);

    expect(find.byKey(const ValueKey('ride-match-offer-panel')), findsNothing);
  });

  testWidgets('accepted offer recovers authoritative canonical ride', (
    tester,
  ) async {
    final center = _center(now);
    center.publishedRoute = _published(now);

    final rideGateway = _RideGateway();

    final rides = DriverRideController(
      gateway: rideGateway,
      repository: rideGateway,
    );

    addTearDown(rides.dispose);

    final offerGateway = _OfferGateway()
      ..loaded = [_offer(now.add(const Duration(minutes: 2)))]
      ..onAccepted = () {
        rideGateway.activeRide = fixtureRide;
      };

    final matches = DriverRideMatchOfferController(
      gateway: offerGateway,
      requestIdGenerator: () => 'request_123456789',
      now: () => now,
    );

    addTearDown(matches.dispose);
    addTearDown(center.dispose);

    await _pumpCenter(tester, center: center, rides: rides, matches: matches);

    await tester.ensureVisible(
      find.byKey(
        const ValueKey(
          'ride-match-offer-accept-'
          'fixture_match_ride',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey(
          'ride-match-offer-accept-'
          'fixture_match_ride',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(offerGateway.acceptCalls, 1);

    expect(offerGateway.requestIds, ['request_123456789']);

    expect(find.text('Yolcunun konumuna gidiliyor'), findsOneWidget);

    expect(rides.ride?.rideId, 'fixture_match_ride');

    expect(rides.ride?.status, RideStatus.driverEnRoute);

    expect(rides.ride?.version, 2);

    expect(find.byKey(const ValueKey('ride-match-offer-panel')), findsNothing);
  });

  testWidgets('without active return route discovery does not run', (
    tester,
  ) async {
    final center = _center(now);

    final rideGateway = _RideGateway();

    final rides = DriverRideController(
      gateway: rideGateway,
      repository: rideGateway,
    );

    addTearDown(rides.dispose);

    final offerGateway = _OfferGateway();

    final matches = DriverRideMatchOfferController(
      gateway: offerGateway,
      requestIdGenerator: () => 'request_123456789',
      now: () => now,
    );

    addTearDown(matches.dispose);
    addTearDown(center.dispose);

    await _pumpCenter(tester, center: center, rides: rides, matches: matches);

    expect(offerGateway.loadCalls, 0);

    expect(find.byKey(const ValueKey('ride-match-offer-panel')), findsNothing);

    expect(find.text('Dönüş Rotanı Oluştur'), findsOneWidget);
  });
}

Future<void> _pumpCenter(
  WidgetTester tester, {
  required DriverCenterController center,
  required DriverRideController rides,
  required DriverRideMatchOfferController matches,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DriverCenterScreen(
        controller: center,
        rideController: rides,
        rideMatchOfferController: matches,
      ),
    ),
  );

  await tester.pumpAndSettle();
}

DriverCenterController _center(DateTime now) => DriverCenterController(
  auth: _Auth(),
  profiles: _Profiles(
    DriverProfile(
      id: 'driver-1',
      authUserId: 'user-1',
      status: DriverProfileStatus.approved,
      createdAt: now.subtract(const Duration(days: 2)),
      approvedAt: now.subtract(const Duration(days: 1)),
    ),
  ),
  passes: _Passes(
    DriverAccessPass(
      id: 'pass-1',
      driverId: 'driver-1',
      plan: DriverPassPlan.daily,
      status: DriverPassStatus.active,
      purchasedAt: now.subtract(const Duration(hours: 2)),
      activatedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.add(const Duration(hours: 1)),
    ),
  ),
  publisher: _Publisher(),
  location: const _Location(),
  now: () => now,
);

PublishedReturnRoute _published(DateTime now, {String routeId = 'route-1'}) {
  final origin = GeoCoordinate(latitude: 41, longitude: 29);

  final destination = GeoCoordinate(latitude: 41.1, longitude: 29.1);

  return PublishedReturnRoute(
    route: DriverReturnRoute(
      id: routeId,
      driverId: 'driver-1',
      origin: origin,
      destination: destination,
      status: DriverReturnRouteStatus.active,
      createdAt: now,
      activatedAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      routeDistanceMeters: 12000,
      routeDurationSeconds: 1800,
      routePoints: [origin, destination],
    ),
    encodedPolyline: 'encoded',
  );
}

RideMatchOffer _offer(DateTime expiresAt) => RideMatchOffer(
  rideId: 'fixture_match_ride',
  rideVersion: 1,
  pickup: const RideLocation(
    latitude: 40.9917,
    longitude: 29.0277,
    addressLabel: 'Kadıköy',
  ),
  dropoff: const RideLocation(
    latitude: 40.9562,
    longitude: 29.0949,
    addressLabel: 'Bostancı',
  ),
  expiresAt: expiresAt,
);

const fixtureRide = CanonicalRide(
  rideId: 'fixture_match_ride',
  driverId: 'driver-1',
  status: RideStatus.driverEnRoute,
  version: 2,
  pickup: RideLocation(
    latitude: 40.9917,
    longitude: 29.0277,
    addressLabel: 'Kadıköy',
  ),
  dropoff: RideLocation(
    latitude: 40.9562,
    longitude: 29.0949,
    addressLabel: 'Bostancı',
  ),
  route: RideRoute(
    distanceMeters: 1400,
    durationSeconds: 420,
    encodedPolyline: 'fixture_polyline',
  ),
);

class _OfferGateway implements RideMatchOfferGateway {
  List<RideMatchOffer> loaded = <RideMatchOffer>[];

  void Function()? onAccepted;

  int loadCalls = 0;
  int acceptCalls = 0;

  final List<String> requestIds = <String>[];

  @override
  Future<List<RideMatchOffer>> getMyRideMatchOffers() async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<void> acceptRideMatchOffer({
    required RideMatchOffer offer,
    required String requestId,
  }) async {
    acceptCalls++;
    requestIds.add(requestId);
    onAccepted?.call();
  }
}

class _RideGateway implements RideGateway, RideStreamRepository {
  CanonicalRide? activeRide;

  @override
  Future<CanonicalRide?> getMyActiveDriverRide() async => activeRide;

  @override
  Stream<CanonicalRide> watchRide(String rideId) => const Stream.empty();

  @override
  Future<CanonicalRide> getRide(String rideId) async => activeRide!;

  @override
  Future<CanonicalRide?> getMyActiveRide() async => null;

  @override
  Future<CanonicalRide> createRide({
    required String requestId,
    required RideLocation pickup,
    required RideLocation dropoff,
  }) => throw UnimplementedError();

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

class _Auth implements DriverCenterAuthGateway {
  @override
  String? get authenticatedUserId => 'user-1';
}

class _Profiles implements DriverProfileRepository {
  const _Profiles(this.value);

  final DriverProfile value;

  @override
  Future<DriverProfile?> findByAuthenticatedUserId(String userId) async =>
      value;
}

class _Passes implements DriverAccessPassRepository {
  const _Passes(this.value);

  final DriverAccessPass value;

  @override
  Future<DriverAccessPass?> findLatestForDriver(String driverId) async => value;
}

class _Location implements LocationAccessGateway {
  const _Location();

  @override
  Future<LocationAccessResult> currentLocation() async =>
      const LocationAccessResult.granted(
        DeviceLocation(latitude: 41, longitude: 29),
      );

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _Publisher implements PublishReturnRouteGateway {
  @override
  Future<PublishedReturnRoute> publish({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
    required int validForSeconds,
  }) => throw UnimplementedError();
}
