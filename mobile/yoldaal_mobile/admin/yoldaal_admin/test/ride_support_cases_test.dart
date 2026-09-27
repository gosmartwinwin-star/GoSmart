import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_admin/application/ride_support_admin_ports.dart';
import 'package:yoldaal_admin/controllers/ride_support_cases_controller.dart';
import 'package:yoldaal_admin/core/admin_exceptions.dart';
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

final class _FakeOperationalGateway
    implements RideSupportAdminReadGateway, RideSupportAdminTransitionGateway {
  _FakeOperationalGateway({this.transitionError});

  RideSupportCaseStatus status = RideSupportCaseStatus.newCase;
  Object? transitionError;
  int listCalls = 0;
  int transitionCalls = 0;
  String? lastRequestId;
  DateTime updatedAt = DateTime.utc(2026, 9, 27, 18);

  @override
  Future<RideSupportCasePage> list({
    int pageSize = 20,
    RideSupportCaseCursor? cursor,
  }) async {
    listCalls++;
    return RideSupportCasePage(
      items: [_item(status: status, updatedAt: updatedAt)],
      nextCursor: null,
    );
  }

  @override
  Future<RideSupportCaseTransitionResult> transition({
    required String rideId,
    required String caseId,
    required RideSupportCaseStatus targetStatus,
    required DateTime expectedUpdatedAt,
    required String requestId,
  }) async {
    transitionCalls++;
    lastRequestId = requestId;
    final error = transitionError;
    if (error != null) throw error;
    expect(rideId, 'ride-1');
    expect(caseId, 'case-1');
    expect(expectedUpdatedAt, updatedAt);
    status = targetStatus;
    updatedAt = updatedAt.add(const Duration(seconds: 1));
    return RideSupportCaseTransitionResult(
      status: status,
      updatedAt: updatedAt,
      idempotent: false,
    );
  }
}

RideSupportCaseSummary _item({
  RideSupportCaseStatus status = RideSupportCaseStatus.newCase,
  DateTime? updatedAt,
}) => RideSupportCaseSummary(
  rideId: 'ride-1',
  caseId: 'case-1',
  reporterRole: RideSupportReporterRole.passenger,
  reporterId: 'passenger-1',
  counterpartyId: 'driver-1',
  category: RideSupportCategory.lostItem,
  reporterNote: 'Telefonumu araçta unuttum.',
  status: status,
  createdAt: DateTime.utc(2026, 9, 27, 18),
  updatedAt: updatedAt ?? DateTime.utc(2026, 9, 27, 18),
);

void main() {
  testWidgets('support inbox renders canonical category, note and status', (
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
    expect(find.text('Durum: Yeni'), findsOneWidget);
    expect(find.text('Ride ID: ride-1'), findsOneWidget);
    expect(find.text('İncelemeye Al'), findsNothing);
  });

  testWidgets('support inbox has a bounded empty state', (tester) async {
    final controller = RideSupportCasesController(
      _FakeGateway([const RideSupportCasePage(items: [], nextCursor: null)]),
    );
    await controller.loadInitial();

    await tester.pumpWidget(
      MaterialApp(home: RideSupportCasesScreen(controller: controller)),
    );

    expect(find.text('Henüz yolculuk bildirimi yok.'), findsOneWidget);
  });

  test(
    'operational transition is forward-only and refreshes after success',
    () async {
      final gateway = _FakeOperationalGateway();
      var request = 0;
      final controller = RideSupportCasesController(
        gateway,
        requestIdFactory: () => 'request-${++request}',
      );
      await controller.loadInitial();

      expect(controller.items.single.status, RideSupportCaseStatus.newCase);
      expect(await controller.advanceStatus(controller.items.single), isTrue);
      expect(gateway.transitionCalls, 1);
      expect(gateway.lastRequestId, 'request-1');
      expect(controller.items.single.status, RideSupportCaseStatus.inReview);

      expect(await controller.advanceStatus(controller.items.single), isTrue);
      expect(gateway.transitionCalls, 2);
      expect(controller.items.single.status, RideSupportCaseStatus.resolved);

      expect(await controller.advanceStatus(controller.items.single), isFalse);
      expect(gateway.transitionCalls, 2);
    },
  );

  test(
    'stale transition is not retried and current state is reloaded',
    () async {
      final gateway = _FakeOperationalGateway(
        transitionError: const AdminPanelException(
          'failed-precondition',
          reason: 'stale_ride_support_case',
        ),
      );
      final controller = RideSupportCasesController(
        gateway,
        requestIdFactory: () => 'request-stale',
      );
      await controller.loadInitial();

      expect(await controller.advanceStatus(controller.items.single), isFalse);
      expect(gateway.transitionCalls, 1);
      expect(gateway.listCalls, 2);
      expect(controller.actionErrorMessage, contains('yeniden yükleniyor'));
    },
  );

  testWidgets('operational gateway shows only the valid next action', (
    tester,
  ) async {
    final gateway = _FakeOperationalGateway();
    final controller = RideSupportCasesController(
      gateway,
      requestIdFactory: () => 'request-ui',
    );
    await controller.loadInitial();

    await tester.pumpWidget(
      MaterialApp(home: RideSupportCasesScreen(controller: controller)),
    );

    expect(find.text('İncelemeye Al'), findsOneWidget);
    expect(find.text('Çözüldü Olarak İşaretle'), findsNothing);
  });
}
