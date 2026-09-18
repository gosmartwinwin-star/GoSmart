import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/screens/profile/profile_screen.dart';

void main() {
  testWidgets(
    'profile account deletion request requires confirmation and reports receipt',
    (tester) async {
      var requestCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            phoneNumber: '+905551234567',
            signOut: () async {},
            requestAccountDeletion: () async {
              requestCount += 1;
            },
          ),
        ),
      );

      expect(
        find.byKey(
          const ValueKey(
            'profile-delete-account',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'profile-delete-account',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(requestCount, 0);

      expect(
        find.byKey(
          const ValueKey(
            'profile-delete-account-confirm',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'profile-delete-account-confirm',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(requestCount, 1);

      expect(
        find.byKey(
          const ValueKey(
            'account-deletion-request-success-close',
          ),
        ),
        findsOneWidget,
      );

      expect(
        find.textContaining(
          'henüz silinmedi',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'account-deletion-request-success-close',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(requestCount, 1);
    },
  );

  testWidgets(
    'failed account deletion request keeps account and surfaces error',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            phoneNumber: '+905551234567',
            signOut: () async {},
            requestAccountDeletion: () async {
              throw StateError('network');
            },
          ),
        ),
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'profile-delete-account',
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey(
            'profile-delete-account-confirm',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'talebi gönderilemedi',
        ),
        findsOneWidget,
      );
    },
  );
}