import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/auth/google_phone_link_runtime_trace.dart';

void main() {
  setUp(googlePhoneLinkRuntimeTrace.clear);
  tearDown(googlePhoneLinkRuntimeTrace.clear);

  test('safe-code allow-list is exact and contains no runtime user values', () {
    expect(
      GooglePhoneLinkRuntimeTrace.allowedCodes,
      equals(<String>{
        'phone_verification_required',
        'phone_verification_requesting',
        'manual_code_required',
        'auto_verification_linking',
        'link_succeeded',
        'direct_google_signed_in',
        'phone_verification_throttled',
        'phone_verification_failed',
        'phone_sign_in_failed',
        'link_unexpected',
        'phone_session_missing',
        'missing_pending_google_link',
        'google_firebase_signin_failed',
        'google_account_link_credential_in_use',
        'google_account_link_account_conflict',
        'google_account_already_linked',
        'google_account_link_network_failed',
        'google_account_link_not_allowed',
        'google_account_link_invalid_credential',
        'google_account_link_reauth_required',
        'google_account_link_user_disabled',
        'google_account_link_internal',
        'google_account_link_failed',
      }),
    );
  });

  test('unknown or arbitrary values are rejected and never recorded', () {
    expect(
      googlePhoneLinkRuntimeTrace.record('arbitrary-runtime-value'),
      isFalse,
    );
    expect(googlePhoneLinkRuntimeTrace.record('user@example.invalid'), isFalse);
    expect(googlePhoneLinkRuntimeTrace.record('+900000000000'), isFalse);

    expect(googlePhoneLinkRuntimeTrace.snapshot(), isEmpty);
    expect(googlePhoneLinkRuntimeTrace.latestCode, isNull);
  });

  test('trace is bounded to newest 32 safe state codes', () {
    final expected = <String>[];

    for (var i = 0; i < 40; i++) {
      final code = i.isEven
          ? 'phone_verification_requesting'
          : 'manual_code_required';

      expect(googlePhoneLinkRuntimeTrace.record(code), isTrue);
      expected.add(code);
    }

    expect(googlePhoneLinkRuntimeTrace.snapshot(), expected.skip(8).toList());
    expect(
      googlePhoneLinkRuntimeTrace.snapshot().length,
      GooglePhoneLinkRuntimeTrace.capacity,
    );
    expect(googlePhoneLinkRuntimeTrace.latestCode, 'manual_code_required');
  });

  test(
    'process-local singleton retains latest safe code until explicit clear',
    () {
      expect(
        googlePhoneLinkRuntimeTrace.record('auto_verification_linking'),
        isTrue,
      );
      expect(
        googlePhoneLinkRuntimeTrace.record(
          'google_account_link_credential_in_use',
        ),
        isTrue,
      );

      expect(
        googlePhoneLinkRuntimeTrace.latestCode,
        'google_account_link_credential_in_use',
      );

      googlePhoneLinkRuntimeTrace.clear();

      expect(googlePhoneLinkRuntimeTrace.latestCode, isNull);
      expect(googlePhoneLinkRuntimeTrace.snapshot(), isEmpty);
    },
  );

  test(
    'LoginScreen restores process-local trace after rebuild and clears it only '
    'when a new Google attempt explicitly starts',
    () {
      final login = File(
        'lib/screens/auth/login_screen.dart',
      ).readAsStringSync();

      expect(
        login,
        contains(
          "import '../../application/auth/"
          "google_phone_link_runtime_trace.dart';",
        ),
      );

      expect(
        login,
        contains(
          '_googlePhoneLinkRuntimeCode = '
          'googlePhoneLinkRuntimeTrace.latestCode;',
        ),
      );

      expect(
        login,
        contains('final recorded = googlePhoneLinkRuntimeTrace.record(code);'),
      );

      expect(login, contains('if (kDebugMode && recorded) {'));

      expect(login, contains('googlePhoneLinkRuntimeTrace.clear();'));

      final start = login.indexOf('Future<void> _startGoogleSignIn() async');
      final clear = login.indexOf(
        'googlePhoneLinkRuntimeTrace.clear();',
        start,
      );
      final coordinatorStart = login.indexOf(
        'await _googleSignInCoordinator.start();',
        start,
      );

      expect(start, greaterThanOrEqualTo(0));
      expect(clear, greaterThan(start));
      expect(coordinatorStart, greaterThan(clear));
    },
  );

  test(
    'trace implementation has no disk, Firebase or secret-bearing storage',
    () {
      final trace = File(
        'lib/application/auth/google_phone_link_runtime_trace.dart',
      ).readAsStringSync();

      for (final forbidden in <String>[
        'SharedPreferences',
        'shared_preferences',
        'dart:io',
        'File(',
        'Firebase',
        'FirebaseAuth',
        'idToken',
        'smsCode',
        'phoneNumber',
        'emailAddress',
        'uid',
        'credential.',
        'DateTime',
      ]) {
        expect(
          trace,
          isNot(contains(forbidden)),
          reason: 'Trace must not contain $forbidden',
        );
      }
    },
  );
}
