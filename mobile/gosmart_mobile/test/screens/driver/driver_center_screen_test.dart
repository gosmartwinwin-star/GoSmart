import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/location/location_access_gateway.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_pass_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_mode_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:gosmart_mobile/application/driver_access/driver_profile_repository.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_repository.dart';
import 'package:gosmart_mobile/application/return_route/publish_return_route_gateway.dart';
import 'package:gosmart_mobile/application/return_route/published_return_route.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_center_controller.dart';
import 'package:gosmart_mobile/controllers/driver_plan_purchase_controller.dart';
import 'package:gosmart_mobile/controllers/driver_ride_controller.dart';
import 'package:gosmart_mobile/core/branding/gosmart_slogans.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_review.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_mode.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';
import 'package:gosmart_mobile/screens/driver/driver_center_screen.dart';

void main() {
  final now = DateTime.utc(2026, 8, 1, 12);
  final origin = GeoCoordinate(latitude: 41, longitude: 29);
  final destination = GeoCoordinate(latitude: 41.1, longitude: 29.1);

  DriverProfile profile(DriverProfileStatus status) => DriverProfile(
    id: 'driver-1',
    authUserId: 'user-1',
    status: status,
    createdAt: now.subtract(const Duration(days: 2)),
    approvedAt: status == DriverProfileStatus.pendingReview
        ? null
        : now.subtract(const Duration(days: 1)),
    suspendedAt: status == DriverProfileStatus.suspended
        ? now.subtract(const Duration(hours: 1))
        : null,
  );
  DriverAccessPass pass() => DriverAccessPass(
    id: 'pass-1',
    driverId: 'driver-1',
    plan: DriverPassPlan.daily,
    status: DriverPassStatus.active,
    purchasedAt: now.subtract(const Duration(hours: 2)),
    activatedAt: now.subtract(const Duration(hours: 1)),
    expiresAt: now.add(const Duration(hours: 1)),
  );
  DriverCenterController controller({
    DriverProfile? loadedProfile,
    DriverAccessPass? loadedPass,
    DriverAccessMode accessMode = DriverAccessMode.paid,
    DriverApplicationReview? application,
    LocationAccessGateway? location,
  }) => DriverCenterController(
    auth: _Auth(),
    profiles: _Profiles(loadedProfile),
    passes: _Passes(loadedPass),
    accessModes: _AccessModes(accessMode),
    publisher: _Publisher(),
    location: location ?? _Location(origin),
    now: () => now,
    applications: application == null ? null : _Applications(application),
  );

  DriverApplicationReview application(DriverApplicationReviewState state) =>
      DriverApplicationReview(
        state: state,
        submissionVersion: 2,
        finalRejectionReason: state == DriverApplicationReviewState.rejected
            ? DriverApplicationFinalRejectionReason.duplicateApplication
            : null,
        documents: [
          for (final type in DriverApplicationDocumentType.values)
            DriverApplicationReviewDocument(
              type: type,
              status:
                  state ==
                          DriverApplicationReviewState
                              .awaitingDocumentResubmission &&
                      type.index == 0
                  ? DriverApplicationPublicDocumentStatus.reuploadRequired
                  : DriverApplicationPublicDocumentStatus.pendingReview,
              reuploadReason:
                  state ==
                          DriverApplicationReviewState
                              .awaitingDocumentResubmission &&
                      type.index == 0
                  ? DriverApplicationReuploadReason.unreadableDocument
                  : null,
            ),
        ],
      );
  Future<void> show(
    WidgetTester tester,
    DriverCenterController value, {
    DriverPlanPurchaseController? purchaseController,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverCenterScreen(
          controller: value,
          driverPlanPurchaseController: purchaseController,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('driver location denied forever renders safe banner', (
    tester,
  ) async {
    final location = _IssueLocation(
      LocationAccessIssue.permissionDeniedForever,
    );

    await show(
      tester,
      controller(
        loadedProfile: profile(DriverProfileStatus.approved),
        loadedPass: pass(),
        location: location,
      ),
    );

    expect(
      find.byKey(const ValueKey('driver-location-access-banner')),
      findsOneWidget,
    );

    expect(find.text('Uygulama Ayarlar\u0131'), findsOneWidget);

    expect(find.textContaining('Exception'), findsNothing);

    await tester.tap(find.text('Uygulama Ayarlar\u0131'));
    await tester.pump();

    expect(location.appSettingsCalls, 1);
  });

  Future<void> showWithRide(
    WidgetTester tester,
    DriverRideController rides,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DriverCenterScreen(
          controller: controller(
            loadedProfile: profile(DriverProfileStatus.approved),
            loadedPass: pass(),
          ),
          rideController: rides,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sürücü sloganı ve profil gerekli kartı gösterilir', (
    tester,
  ) async {
    await show(tester, controller());
    expect(find.text(GoSmartSlogans.driver), findsOneWidget);
    expect(find.text('Sürücü profili gerekli'), findsOneWidget);
  });

  testWidgets(
    'profil gerekli durumda aktif sürücü yolculuğu recovery çağrılmaz',
    (tester) async {
      final gateway = _RideGateway();
      final rides = DriverRideController(gateway: gateway, repository: gateway);
      addTearDown(rides.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DriverCenterScreen(
            controller: controller(),
            rideController: rides,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(gateway.activeDriverRideCalls, 0);
      expect(find.text('Sürücü profili gerekli'), findsOneWidget);
      expect(find.text('Aktif yolculuk yüklenemedi'), findsNothing);
    },
  );

  testWidgets('root driver surface keeps profile access', (tester) async {
    await show(tester, controller());
    expect(find.byTooltip('Profil'), findsOneWidget);
  });
  testWidgets('pending profil kartı gösterilir', (tester) async {
    await show(
      tester,
      controller(loadedProfile: profile(DriverProfileStatus.pendingReview)),
    );
    expect(find.text('Profiliniz inceleniyor'), findsOneWidget);
  });
  testWidgets('kontör gerekli kartı gösterilir', (tester) async {
    await show(
      tester,
      controller(loadedProfile: profile(DriverProfileStatus.approved)),
    );
    expect(find.text('Aktif kontör paketi gerekli'), findsOneWidget);
  });
  testWidgets('paid approved driver without pass shows purchase panel', (
    tester,
  ) async {
    final purchase = DriverPlanPurchaseController(
      gateway: _PurchaseGateway(),
      requestIdFactory: () => 'screen-request',
    );
    addTearDown(purchase.dispose);

    await show(
      tester,
      controller(loadedProfile: profile(DriverProfileStatus.approved)),
      purchaseController: purchase,
    );

    expect(find.text('Aktif kontör paketi gerekli'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('driver-plan-purchase-panel')),
      findsOneWidget,
    );
    expect(find.text('Günlük'), findsOneWidget);
    expect(find.text('Haftalık'), findsOneWidget);
    expect(find.text('Aylık'), findsOneWidget);
    expect(find.text('3 Aylık'), findsOneWidget);
  });

  testWidgets('launchFree driver never sees purchase panel', (tester) async {
    final purchase = DriverPlanPurchaseController(
      gateway: _PurchaseGateway(),
      requestIdFactory: () => 'screen-request',
    );
    addTearDown(purchase.dispose);

    await show(
      tester,
      controller(
        loadedProfile: profile(DriverProfileStatus.approved),
        accessMode: DriverAccessMode.launchFree,
      ),
      purchaseController: purchase,
    );

    expect(
      find.byKey(const ValueKey('driver-plan-purchase-panel')),
      findsNothing,
    );
  });

  testWidgets('active pass ready driver never sees purchase panel', (
    tester,
  ) async {
    final purchase = DriverPlanPurchaseController(
      gateway: _PurchaseGateway(),
      requestIdFactory: () => 'screen-request',
    );
    addTearDown(purchase.dispose);

    await show(
      tester,
      controller(
        loadedProfile: profile(DriverProfileStatus.approved),
        loadedPass: pass(),
      ),
      purchaseController: purchase,
    );

    expect(
      find.byKey(const ValueKey('driver-plan-purchase-panel')),
      findsNothing,
    );
  });

  testWidgets('non-subscription restriction never shows purchase panel', (
    tester,
  ) async {
    final purchase = DriverPlanPurchaseController(
      gateway: _PurchaseGateway(),
      requestIdFactory: () => 'screen-request',
    );
    addTearDown(purchase.dispose);

    await show(
      tester,
      controller(
        loadedProfile: profile(DriverProfileStatus.suspended),
        accessMode: DriverAccessMode.launchFree,
      ),
      purchaseController: purchase,
    );

    expect(
      find.byKey(const ValueKey('driver-plan-purchase-panel')),
      findsNothing,
    );
  });
  testWidgets('launchFree ready surface shows free launch card', (
    tester,
  ) async {
    await show(
      tester,
      controller(
        loadedProfile: profile(DriverProfileStatus.approved),
        accessMode: DriverAccessMode.launchFree,
      ),
    );

    expect(find.text('Lansman d\u00f6neminde \u00fccretsiz'), findsOneWidget);
    expect(
      find.text(
        'GoSmart, lansman d\u00f6neminde s\u00fcr\u00fcc\u00fcler i\u00e7in \u00fccretsizdir. '
        'S\u00fcr\u00fcc\u00fc eri\u015fimi i\u00e7in abonelik veya paket \u00fccreti al\u0131nmaz.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('D\u00f6n\u00fc\u015f Rotan\u0131 Olu\u015ftur'),
      findsOneWidget,
    );
    expect(find.text('Aktif kont\u00f6r paketi gerekli'), findsNothing);
  });
  testWidgets('ready durumda form ve süre seçenekleri gösterilir', (
    tester,
  ) async {
    await show(
      tester,
      controller(
        loadedProfile: profile(DriverProfileStatus.approved),
        loadedPass: pass(),
      ),
    );
    expect(find.text('Dönüş Rotanı Oluştur'), findsOneWidget);
    for (final label in ['15 dk', '30 dk', '1 saat', '2 saat', '4 saat']) {
      expect(find.text(label), findsOneWidget);
    }
    final selected = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '1 saat'),
    );
    expect(selected.selected, isTrue);
  });
  testWidgets('hedef yokken yayınlama butonu kapalıdır', (tester) async {
    await show(
      tester,
      controller(
        loadedProfile: profile(DriverProfileStatus.approved),
        loadedPass: pass(),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Dönüş Rotasını Yayınla'),
    );
    expect(button.onPressed, isNull);
  });
  testWidgets('tüm girdiler hazırken yayınlama butonu aktiftir', (
    tester,
  ) async {
    final value = controller(
      loadedProfile: profile(DriverProfileStatus.approved),
      loadedPass: pass(),
    );
    await show(tester, value);
    value.selectDestination(destination, 'Ev');
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Dönüş Rotasını Yayınla'),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('İptal Et'), findsNothing);
    expect(find.text('Duraklat'), findsNothing);
  });

  testWidgets('fixture recovery aktif driver ride kartını öncelikli gösterir', (
    tester,
  ) async {
    final gateway = _RideGateway()..activeRide = fixtureRide;
    final rides = DriverRideController(gateway: gateway, repository: gateway);
    addTearDown(rides.dispose);

    await showWithRide(tester, rides);

    expect(find.text('Yolcunun konumuna gidiliyor'), findsOneWidget);
    expect(find.text('Teslim Alma Noktasına Ulaştım'), findsOneWidget);
    expect(find.text('Dönüş Rotanı Oluştur'), findsNothing);
  });

  testWidgets('null active ride dönüş rotası yüzeyini gösterir', (
    tester,
  ) async {
    final gateway = _RideGateway();
    final rides = DriverRideController(gateway: gateway, repository: gateway);
    addTearDown(rides.dispose);

    await showWithRide(tester, rides);

    expect(find.text('Dönüş Rotanı Oluştur'), findsOneWidget);
    expect(find.text('Aktif yolculuk yüklenemedi'), findsNothing);
  });

  testWidgets('recovery hatası güvenli retry yüzeyi gösterir', (tester) async {
    final gateway = _RideGateway()
      ..recoveryError = const RideGatewayException('unavailable');
    final rides = DriverRideController(gateway: gateway, repository: gateway);
    addTearDown(rides.dispose);

    await showWithRide(tester, rides);

    expect(find.text('Aktif yolculuk yüklenemedi'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
    expect(find.text('Dönüş Rotanı Oluştur'), findsNothing);
  });

  testWidgets('awaiting state only offers document renewal', (tester) async {
    await show(
      tester,
      controller(
        application: application(
          DriverApplicationReviewState.awaitingDocumentResubmission,
        ),
      ),
    );
    expect(find.text('Belge Yenileme Gerekli'), findsOneWidget);
    expect(find.text('Belgeleri Yenile'), findsOneWidget);
    expect(find.text('Yeniden Başvur'), findsNothing);
  });

  testWidgets('final rejected is read-only with safe reason', (tester) async {
    await show(
      tester,
      controller(
        application: application(DriverApplicationReviewState.rejected),
      ),
    );
    expect(find.text('Başvurunuz reddedildi'), findsOneWidget);
    expect(find.text('Tekrarlanan başvuru.'), findsOneWidget);
    expect(find.text('Yeniden Başvur'), findsNothing);
  });

  testWidgets('withdrawn has no generic reapply action', (tester) async {
    await show(
      tester,
      controller(
        application: application(DriverApplicationReviewState.withdrawn),
      ),
    );
    expect(find.text('Başvurunuz geri çekildi'), findsOneWidget);
    expect(find.text('Yeniden Başvur'), findsNothing);
  });
}

const fixturePoint = RideLocation(
  latitude: 41.0082,
  longitude: 28.9784,
  addressLabel: 'Fixture pickup',
);
const fixtureRide = CanonicalRide(
  rideId: 'fixture_assigned_ride',
  driverId: 'fixture_driver_profile',
  status: RideStatus.driverEnRoute,
  version: 2,
  pickup: fixturePoint,
  dropoff: RideLocation(
    latitude: 41.0151,
    longitude: 28.9795,
    addressLabel: 'Fixture dropoff',
  ),
  route: RideRoute(
    distanceMeters: 1400,
    durationSeconds: 420,
    encodedPolyline: 'fixture_polyline',
  ),
);

class _RideGateway implements RideGateway, RideStreamRepository {
  CanonicalRide? activeRide;
  RideGatewayException? recoveryError;
  int activeDriverRideCalls = 0;

  @override
  Future<CanonicalRide?> getMyActiveDriverRide() async {
    activeDriverRideCalls += 1;
    if (recoveryError case final error?) throw error;
    return activeRide;
  }

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

class _Applications implements DriverApplicationRepository {
  _Applications(this.value);
  final DriverApplicationReview value;
  @override
  Future<DriverApplicationReview?> findForAuthenticatedUser() async => value;
}

class _Auth implements DriverCenterAuthGateway {
  @override
  String? get authenticatedUserId => 'user-1';
}

class _Profiles implements DriverProfileRepository {
  final DriverProfile? value;
  _Profiles(this.value);
  @override
  Future<DriverProfile?> findByAuthenticatedUserId(String id) async => value;
}

class _Passes implements DriverAccessPassRepository {
  final DriverAccessPass? value;
  _Passes(this.value);
  @override
  Future<DriverAccessPass?> findLatestForDriver(String id) async => value;
}

class _AccessModes implements DriverAccessModeRepository {
  const _AccessModes(this.value);

  final DriverAccessMode value;

  @override
  Future<DriverAccessMode> load() async => value;
}

class _PurchaseGateway implements DriverPlanPurchaseGateway {
  @override
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  }) async {
    return PreparedDriverPlanPurchase(
      purchaseOperationId: List<String>.filled(64, 'a').join(),
      status: 'pending',
      catalogVersion: 'catalog_v1',
      plan: plan,
      amountMinor: 1234,
      currency: 'EUR',
    );
  }
}

class _Location implements LocationAccessGateway {
  _Location(this.value);

  final GeoCoordinate value;

  @override
  Future<LocationAccessResult> currentLocation() async =>
      LocationAccessResult.granted(
        DeviceLocation(latitude: value.latitude, longitude: value.longitude),
      );

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _IssueLocation implements LocationAccessGateway {
  _IssueLocation(this.issue);

  final LocationAccessIssue issue;
  int appSettingsCalls = 0;

  @override
  Future<LocationAccessResult> currentLocation() async =>
      LocationAccessResult.failed(issue);

  @override
  Future<bool> openAppSettings() async {
    appSettingsCalls++;
    return true;
  }

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
