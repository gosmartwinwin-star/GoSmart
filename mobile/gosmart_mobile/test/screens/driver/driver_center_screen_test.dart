import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_pass_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_profile_repository.dart';
import 'package:gosmart_mobile/application/return_route/publish_return_route_gateway.dart';
import 'package:gosmart_mobile/application/return_route/published_return_route.dart';
import 'package:gosmart_mobile/controllers/driver_center_controller.dart';
import 'package:gosmart_mobile/core/branding/gosmart_slogans.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
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
  }) => DriverCenterController(
    auth: _Auth(),
    profiles: _Profiles(loadedProfile),
    passes: _Passes(loadedPass),
    publisher: _Publisher(),
    location: _Location(origin),
    now: () => now,
  );
  Future<void> show(WidgetTester tester, DriverCenterController value) async {
    await tester.pumpWidget(
      MaterialApp(home: DriverCenterScreen(controller: value)),
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

class _Location implements DriverLocationGateway {
  final GeoCoordinate value;
  _Location(this.value);
  @override
  Future<GeoCoordinate> currentLocation() async => value;
}

class _Publisher implements PublishReturnRouteGateway {
  @override
  Future<PublishedReturnRoute> publish({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
    required int validForSeconds,
  }) => throw UnimplementedError();
}
