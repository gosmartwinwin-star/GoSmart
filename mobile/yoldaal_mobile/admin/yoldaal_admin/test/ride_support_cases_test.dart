import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_admin/application/ride_support_admin_ports.dart';
import 'package:yoldaal_admin/controllers/ride_support_cases_controller.dart';
import 'package:yoldaal_admin/domain/ride_support_case.dart';
import 'package:yoldaal_admin/screens/ride_support_cases_screen.dart';

final class _FakeGateway implements RideSupportAdminReadGateway {
  _FakeGateway(this.pages);
  final List<RideSupportCasePage> pages;
  int calls = 0;

  @override
  Future<RideSupportCasePage> list({
    int pageSize = 20,
    RideSupportCaseCursor? cursor,
  }) async => pages[calls++];
}

RideSupportCaseSummary _item() => RideSupportCaseSummary(
  rideId: 'ride-1',
  caseId: 'case-1',
  reporterRole: RideSupportReporterRole.passenger,
  reporterId: 'passenger-1',
  counterpartyId: 'driver-1',
  category: RideSupportCategory.lostItem,
  reporterNote: 'Telefonumu araçta unuttum.',
  createdAt: DateTime.utc(2026, 9, 27, 18),
  updatedAt: DateTime.utc(2026, 9, 27, 18),
);

void main() {
  testWidgets('support inbox renders canonical category and optional note', (
    tester,
  ) async {
    final controller = RideSupportCasesController(
      _FakeGateway([
        RideSupportCasePage(items: [_item()], nextCursor: null),
      ]),
    );
    await controller.loadInitial();

    await tester.pumpWidget(
      MaterialApp(home: RideSupportCasesScreen(controller: controller)),
    );

    expect(find.text('Yolculuk Bildirimleri'), findsOneWidget);
    expect(find.text('Unutulan eşya'), findsOneWidget);
    expect(find.text('Telefonumu araçta unuttum.'), findsOneWidget);
    expect(find.text('Ride ID: ride-1'), findsOneWidget);
  });

  testWidgets('support inbox has a bounded empty state', (tester) async {
    final controller = RideSupportCasesController(
      _FakeGateway([
        const RideSupportCasePage(items: [], nextCursor: null),
      ]),
    );
    await controller.loadInitial();

    await tester.pumpWidget(
      MaterialApp(home: RideSupportCasesScreen(controller: controller)),
    );

    expect(find.text('Henüz yolculuk bildirimi yok.'), findsOneWidget);
  });
}
