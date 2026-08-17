import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/location/location_access_gateway.dart';
import 'package:gosmart_mobile/widgets/location/location_access_banner.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    LocationAccessIssue issue, {
    required VoidCallback onAction,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationAccessBanner(issue: issue, onAction: onAction),
        ),
      ),
    );
  }

  testWidgets('serviceDisabled konum ayarlarini sunar', (tester) async {
    var calls = 0;

    await show(
      tester,
      LocationAccessIssue.serviceDisabled,
      onAction: () => calls++,
    );

    expect(find.text('Konum Ayarları'), findsOneWidget);

    expect(find.textContaining('Konum servisi kapalı'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('location-access-action')));

    expect(calls, 1);
  });

  testWidgets('permissionDenied yeniden deneme sunar', (tester) async {
    await show(tester, LocationAccessIssue.permissionDenied, onAction: () {});

    expect(find.text('Tekrar Dene'), findsOneWidget);

    expect(find.textContaining('Konum izni verilmedi'), findsOneWidget);
  });

  testWidgets('permissionDeniedForever uygulama ayarlarini sunar', (
    tester,
  ) async {
    await show(
      tester,
      LocationAccessIssue.permissionDeniedForever,
      onAction: () {},
    );

    expect(find.text('Uygulama Ayarları'), findsOneWidget);

    expect(find.textContaining('uygulama ayarlarından'), findsOneWidget);
  });

  testWidgets('unavailable kontrollu generic mesaj verir', (tester) async {
    await show(tester, LocationAccessIssue.unavailable, onAction: () {});

    expect(find.text('Tekrar Dene'), findsOneWidget);

    expect(find.textContaining('şu anda alınamadı'), findsOneWidget);

    expect(find.textContaining('Exception'), findsNothing);
  });
}
