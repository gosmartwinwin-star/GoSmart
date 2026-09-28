import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/screens/profile/profile_screen.dart';
import 'package:yoldaal_mobile/services/account_deletion_execution_service.dart';

void main() {
  testWidgets('cancel leaves request execution and sign-out untouched', (
    tester,
  ) async {
    var requestCount = 0;
    var executeCount = 0;
    var signOutCount = 0;

    await _pumpProfile(
      tester,
      request: () async => requestCount++,
      execute: () async {
        executeCount++;
        return _completed();
      },
      signOut: () async => signOutCount++,
    );

    await tester.tap(find.byKey(const ValueKey('profile-delete-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();

    expect(requestCount, 0);
    expect(executeCount, 0);
    expect(signOutCount, 0);
  });

  testWidgets(
    'completed deletion runs request then execute then immediate sign-out',
    (tester) async {
      final events = <String>[];

      await _pumpProfile(
        tester,
        request: () async => events.add('request'),
        execute: () async {
          events.add('execute');
          return _completed();
        },
        signOut: () async => events.add('signOut'),
      );

      await _confirmDeletion(tester);
      await tester.pumpAndSettle();

      expect(events, ['request', 'execute', 'signOut']);
      expect(
        find.byKey(const ValueKey('account-deletion-completed-close')),
        findsNothing,
      );
      expect(find.text('Hesap Silindi'), findsNothing);
    },
  );
  testWidgets('processing keeps session and reports pending state', (
    tester,
  ) async {
    var signOutCount = 0;

    await _pumpProfile(
      tester,
      request: () async {},
      execute: () async => const AccountDeletionExecutionResult(
        status: AccountDeletionExecutionStatus.processing,
        idempotent: true,
      ),
      signOut: () async => signOutCount++,
    );

    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(signOutCount, 0);
    expect(
      find.byKey(const ValueKey('account-deletion-processing-close')),
      findsOneWidget,
    );
    expect(find.textContaining('devam ediyor'), findsWidgets);
  });

  testWidgets('request failure stops before execution and preserves session', (
    tester,
  ) async {
    var executeCount = 0;
    var signOutCount = 0;

    await _pumpProfile(
      tester,
      request: () async => throw StateError('network'),
      execute: () async {
        executeCount++;
        return _completed();
      },
      signOut: () async => signOutCount++,
    );

    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(executeCount, 0);
    expect(signOutCount, 0);
    expect(find.textContaining('başlatılamadı'), findsOneWidget);
  });

  testWidgets('active ride block preserves session and shows controlled text', (
    tester,
  ) async {
    var signOutCount = 0;

    await _pumpProfile(
      tester,
      request: () async {},
      execute: () async => throw const AccountDeletionExecutionException(
        code: 'failed-precondition',
        reason: 'active_ride_blocks_account_deletion',
      ),
      signOut: () async => signOutCount++,
    );

    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(signOutCount, 0);
    expect(
      find.text('Aktif yolculuğunuz tamamlanmadan hesabınızı silemezsiniz.'),
      findsOneWidget,
    );
  });

  testWidgets('execution failure preserves session and fails closed', (
    tester,
  ) async {
    var signOutCount = 0;

    await _pumpProfile(
      tester,
      request: () async {},
      execute: () async =>
          throw const AccountDeletionExecutionException(code: 'unavailable'),
      signOut: () async => signOutCount++,
    );

    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(signOutCount, 0);
    expect(find.textContaining('tamamlanamadı'), findsOneWidget);
  });

  testWidgets('in-flight deletion disables delete and sign-out controls', (
    tester,
  ) async {
    final requestCompleter = Completer<void>();
    var requestCount = 0;
    var executeCount = 0;

    await _pumpProfile(
      tester,
      request: () {
        requestCount++;
        return requestCompleter.future;
      },
      execute: () async {
        executeCount++;
        return const AccountDeletionExecutionResult(
          status: AccountDeletionExecutionStatus.processing,
          idempotent: true,
        );
      },
      signOut: () async {},
    );

    await _confirmDeletion(tester, settleAfterConfirm: false);
    await tester.pump();

    expect(requestCount, 1);
    expect(executeCount, 0);
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('profile-delete-account')),
          )
          .onTap,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );

    requestCompleter.complete();
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(executeCount, 1);
  });
}

AccountDeletionExecutionResult _completed() =>
    const AccountDeletionExecutionResult(
      status: AccountDeletionExecutionStatus.completed,
      idempotent: false,
    );

Future<void> _pumpProfile(
  WidgetTester tester, {
  required AccountDeletionRequestCallback request,
  required AccountDeletionExecutionCallback execute,
  required SignOutCallback signOut,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(
        phoneNumber: '+905551234567',
        requestAccountDeletion: request,
        executeAccountDeletion: execute,
        signOut: signOut,
      ),
    ),
  );
}

Future<void> _confirmDeletion(
  WidgetTester tester, {
  bool settleAfterConfirm = true,
}) async {
  await tester.tap(find.byKey(const ValueKey('profile-delete-account')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('profile-delete-account-confirm')),
  );
  if (settleAfterConfirm) {
    await tester.pumpAndSettle();
  }
}
