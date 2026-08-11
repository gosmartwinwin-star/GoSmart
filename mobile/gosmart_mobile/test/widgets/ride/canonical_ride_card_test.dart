import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/widgets/ride/canonical_ride_card.dart';

void main() {
  CanonicalRide ride(RideStatus status) => CanonicalRide(
    rideId: 'ride-1', status: status, version: 1,
    pickup: const RideLocation(latitude: 41, longitude: 29, addressLabel: 'Alış'),
    dropoff: const RideLocation(latitude: 42, longitude: 30, addressLabel: 'Varış'),
    route: const RideRoute(distanceMeters: 1, durationSeconds: 1, encodedPolyline: 'x'),
  );
  Future<void> show(WidgetTester tester, RideStatus status, {bool driver = false, VoidCallback? primary, VoidCallback? cancel, VoidCallback? dismiss, bool loading = false}) => tester.pumpWidget(MaterialApp(home: Scaffold(body: CanonicalRideCard(ride: ride(status), driver: driver, loading: loading, onPrimary: primary, onCancel: cancel, onDismiss: dismiss))));
  testWidgets('passenger canonical durum metinlerini gösterir', (tester) async {
    final labels = {RideStatus.matching: 'Sürücü aranıyor', RideStatus.driverEnRoute: 'Sürücü teslim alma noktasına geliyor', RideStatus.driverArrived: 'Sürücü teslim alma noktasına ulaştı', RideStatus.inProgress: 'Yolculuk devam ediyor', RideStatus.completed: 'Yolculuk tamamlandı', RideStatus.cancelled: 'Yolculuk iptal edildi', RideStatus.expired: 'Sürücü bulunamadı'};
    for (final entry in labels.entries) { await show(tester, entry.key); expect(find.text(entry.value), findsOneWidget); }
  });
  testWidgets('passenger cancel görünürlüğü dışarıdan kontrollüdür ve loading disable eder', (tester) async { await show(tester, RideStatus.matching, cancel: () {}, loading: true); final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Yolculuğu İptal Et')); expect(button.onPressed, isNull); await show(tester, RideStatus.inProgress); expect(find.text('Yolculuğu İptal Et'), findsNothing); });
  testWidgets('driver state için yalnız doğru primary action gösterilir', (tester) async { await show(tester, RideStatus.driverEnRoute, driver: true, primary: () {}); expect(find.text('Teslim Alma Noktasına Ulaştım'), findsOneWidget); await show(tester, RideStatus.driverArrived, driver: true, primary: () {}); expect(find.text('Yolculuğu Başlat'), findsOneWidget); await show(tester, RideStatus.inProgress, driver: true, primary: () {}); expect(find.text('Yolculuğu Tamamla'), findsOneWidget); });
  testWidgets('terminal ride mutation action göstermez', (tester) async { await show(tester, RideStatus.completed, driver: true); expect(find.byType(FilledButton), findsNothing); expect(find.text('Yolculuğu İptal Et'), findsNothing); });
}
