import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/screens/profile/profile_screen.dart';

void main() {
  testWidgets('profile exposes ride history navigation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          phoneNumber: '+905551234567',
          historyScreenBuilder: (_) =>
              const Scaffold(body: Text('history-fixture')),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('profile-ride-history')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-ride-history')));

    await tester.pumpAndSettle();

    expect(find.text('history-fixture'), findsOneWidget);
  });
}
