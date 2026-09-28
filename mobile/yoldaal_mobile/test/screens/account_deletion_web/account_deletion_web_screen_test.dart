import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/screens/account_deletion_web/account_deletion_web_screen.dart';
import 'package:yoldaal_mobile/services/account_deletion_execution_service.dart';
import 'package:yoldaal_mobile/services/account_deletion_web_auth_service.dart';

void main() {
  const user = AccountDeletionWebAuthUser(
    uid: 'uid-1',
    phoneNumber: '+905551234567',
    providerIds: <String>['phone'],
  );

  testWidgets('google auth establishes visible authenticated identity', (
    tester,
  ) async {
    await _pump(tester, initialUser: null, signInWithGoogle: () async => user);

    await tester.tap(
      find.byKey(const ValueKey('account-deletion-web-google-sign-in')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('account-deletion-web-authenticated-identity')),
      findsOneWidget,
    );
    expect(find.textContaining('+905551234567'), findsOneWidget);
  });

  testWidgets('phone flow sends code then confirms authenticated identity', (
    tester,
  ) async {
    String? phone;
    String? code;

    await _pump(
      tester,
      initialUser: null,
      startPhoneSignIn: (value) async {
        phone = value;
      },
      confirmPhoneCode: (value) async {
        code = value;
        return user;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('account-deletion-web-phone')),
      '+905551234567',
    );
    await tester.tap(
      find.byKey(const ValueKey('account-deletion-web-send-phone-code')),
    );
    await tester.pumpAndSettle();

    expect(phone, '+905551234567');
    expect(
      find.byKey(const ValueKey('account-deletion-web-phone-code')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('account-deletion-web-phone-code')),
      '123456',
    );
    final confirmPhoneCodeButton = find.byKey(
      const ValueKey('account-deletion-web-confirm-phone-code'),
    );
    await tester.ensureVisible(confirmPhoneCodeButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmPhoneCodeButton);
    await tester.pumpAndSettle();

    expect(code, '123456');
    expect(
      find.byKey(const ValueKey('account-deletion-web-authenticated-identity')),
      findsOneWidget,
    );
  });

  testWidgets('cancel does not request execute or sign out', (tester) async {
    var requestCount = 0;
    var executeCount = 0;
    var signOutCount = 0;

    await _pump(
      tester,
      initialUser: user,
      requestDeletion: () async => requestCount++,
      executeDeletion: () async {
        executeCount++;
        return _completed();
      },
      signOut: () async => signOutCount++,
    );

    await _enableDeletion(tester);
    await tester.tap(find.byKey(const ValueKey('account-deletion-web-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(requestCount, 0);
    expect(executeCount, 0);
    expect(signOutCount, 0);
  });

  testWidgets('completed runs request then execute then immediate sign-out', (
    tester,
  ) async {
    final events = <String>[];

    await _pump(
      tester,
      initialUser: user,
      requestDeletion: () async => events.add('request'),
      executeDeletion: () async {
        events.add('execute');
        return _completed();
      },
      signOut: () async => events.add('signOut'),
    );

    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(events, <String>['request', 'execute', 'signOut']);
    expect(find.textContaining('kalıcı olarak silindi'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('account-deletion-web-delete')),
      findsNothing,
    );
  });

  testWidgets('processing keeps session signed in', (tester) async {
    var signOutCount = 0;

    await _pump(
      tester,
      initialUser: user,
      executeDeletion: () async => const AccountDeletionExecutionResult(
        status: AccountDeletionExecutionStatus.processing,
        idempotent: true,
      ),
      signOut: () async => signOutCount++,
    );

    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(signOutCount, 0);
    expect(find.textContaining('devam ediyor'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('account-deletion-web-authenticated-identity')),
      findsOneWidget,
    );
  });

  testWidgets('request failure stops before execution and keeps session', (
    tester,
  ) async {
    var executeCount = 0;
    var signOutCount = 0;

    await _pump(
      tester,
      initialUser: user,
      requestDeletion: () async => throw StateError('network'),
      executeDeletion: () async {
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

  testWidgets('active ride block keeps session and shows controlled message', (
    tester,
  ) async {
    var signOutCount = 0;

    await _pump(
      tester,
      initialUser: user,
      executeDeletion: () async =>
          throw const AccountDeletionExecutionException(
            code: 'failed-precondition',
            reason: 'active_ride_blocks_account_deletion',
          ),
      signOut: () async => signOutCount++,
    );

    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(signOutCount, 0);
    expect(
      find.textContaining('Aktif veya tamamlanmamış yolculuğunuz'),
      findsOneWidget,
    );
  });

  testWidgets('execution failure fails closed and keeps session', (
    tester,
  ) async {
    var signOutCount = 0;

    await _pump(
      tester,
      initialUser: user,
      executeDeletion: () async =>
          throw const AccountDeletionExecutionException(code: 'unavailable'),
      signOut: () async => signOutCount++,
    );

    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(signOutCount, 0);
    expect(find.textContaining('tamamlanamadı'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('account-deletion-web-authenticated-identity')),
      findsOneWidget,
    );
  });

  testWidgets('malformed execution failure is bounded and keeps session', (
    tester,
  ) async {
    var signOutCount = 0;

    await _pump(
      tester,
      initialUser: user,
      executeDeletion: () async => throw StateError('malformed response'),
      signOut: () async => signOutCount++,
    );

    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(signOutCount, 0);
    expect(
      find.textContaining('güvenli şekilde tamamlanamadı'),
      findsOneWidget,
    );
  });

  testWidgets('in-flight deletion disables destructive and sign-out controls', (
    tester,
  ) async {
    final requestCompleter = Completer<void>();
    var requestCount = 0;
    var executeCount = 0;

    await _pump(
      tester,
      initialUser: user,
      requestDeletion: () {
        requestCount++;
        return requestCompleter.future;
      },
      executeDeletion: () async {
        executeCount++;
        return const AccountDeletionExecutionResult(
          status: AccountDeletionExecutionStatus.processing,
          idempotent: true,
        );
      },
    );

    await _enableDeletion(tester);
    await tester.tap(find.byKey(const ValueKey('account-deletion-web-delete')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('account-deletion-web-confirm-delete')),
    );
    await tester.pump();

    expect(requestCount, 1);
    expect(executeCount, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('account-deletion-web-delete')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('account-deletion-web-sign-out')),
          )
          .onPressed,
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

Future<void> _pump(
  WidgetTester tester, {
  AccountDeletionWebAuthUser? initialUser,
  AccountDeletionWebGoogleSignInCallback? signInWithGoogle,
  AccountDeletionWebPhoneStartCallback? startPhoneSignIn,
  AccountDeletionWebPhoneConfirmCallback? confirmPhoneCode,
  AccountDeletionWebRequestCallback? requestDeletion,
  AccountDeletionWebExecutionCallback? executeDeletion,
  AccountDeletionWebSignOutCallback? signOut,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AccountDeletionWebScreen(
        initialUser: initialUser,
        signInWithGoogle: signInWithGoogle ?? () async => initialUser!,
        startPhoneSignIn: startPhoneSignIn ?? (_) async {},
        confirmPhoneCode: confirmPhoneCode ?? (_) async => initialUser!,
        requestDeletion: requestDeletion ?? () async {},
        executeDeletion: executeDeletion ?? () async => _completed(),
        signOut: signOut ?? () async {},
      ),
    ),
  );
}

Future<void> _enableDeletion(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('account-deletion-web-identity-confirmation')),
  );
  await tester.pump();
}

Future<void> _confirmDeletion(WidgetTester tester) async {
  await _enableDeletion(tester);
  await tester.tap(find.byKey(const ValueKey('account-deletion-web-delete')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('account-deletion-web-confirm-delete')),
  );
}
