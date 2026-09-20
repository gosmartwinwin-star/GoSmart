import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android automatic phone verification exposes linking progress', () {
    final source = File(
      'lib/screens/auth/login_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_googleAutoVerificationInProgress'));
    expect(
      source,
      contains('final googlePhoneLinkRequest = _googlePhoneLinkPending;'),
    );
    expect(
      source,
      contains('final googleAutoVerification = googlePhoneLinkRequest;'),
    );
    expect(source, contains('Telefon numaranız otomatik doğrulandı.'));
    expect(source, contains('Google hesabınız bağlanıyor.'));
    expect(source, contains('await _completeSignIn(credential);'));
  });

  test('Google link Firebase exceptions retain safe classifications', () {
    final source = File(
      'lib/services/google_sign_in_service.dart',
    ).readAsStringSync();

    expect(source, contains('on FirebaseAuthException catch (error)'));

    for (final value in <String>[
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
    ]) {
      expect(source, contains(value));
    }
  });

  test(
    'Google link classifications use explicit safe UX then existing fallback',
    () {
      final source = File(
        'lib/screens/auth/login_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_messageForGoogleLinkRuntimeError(error)'));

      expect(
        source,
        contains('Bu Google hesabı başka bir YoldaAl hesabına bağlı.'),
      );

      expect(source, contains('Google oturumu geçersizleşti.'));

      expect(source, contains('return _messageForGoogleError(error);'));
    },
  );

  test('existing post-session rollback path remains wired', () {
    final source = File(
      'lib/screens/auth/login_screen.dart',
    ).readAsStringSync();

    expect(source, contains('if (phoneSessionOpened)'));

    expect(source, contains('await _abortGooglePhoneLink();'));

    expect(source, contains('_googleSignInCoordinator.clearPendingLink();'));

    expect(source, contains('authTransitionHold.release();'));
  });
  test('runtime state persists safe outcomes beyond transient snackbars', () {
    final source = File(
      'lib/screens/auth/login_screen.dart',
    ).readAsStringSync();

    expect(source, contains('String? _googlePhoneLinkRuntimeCode;'));
    expect(source, contains('_recordGooglePhoneLinkRuntimeState(error.code);'));
    expect(source, contains(r'Google phone-link safe state: $code'));
    expect(source, contains('final googlePhoneLinkRuntimeMessage ='));
    expect(source, contains(r'Güvenli durum: $_googlePhoneLinkRuntimeCode'));

    for (final value in <String>[
      'phone_verification_required',
      'phone_verification_requesting',
      'manual_code_required',
      'auto_verification_linking',
      'link_succeeded',
      'phone_verification_failed',
      'phone_sign_in_failed',
      'link_unexpected',
    ]) {
      expect(source, contains(value));
    }

    expect(source, isNot(contains('error.message')));
  });

  test(
    'too-many-requests creates a process-local no-auto-retry throttle guard',
    () {
      final source = File(
        'lib/screens/auth/login_screen.dart',
      ).readAsStringSync();

      expect(source, contains('_phoneVerificationThrottled'));
      expect(source, contains("error.code == 'too-many-requests'"));
      expect(source, contains('_phoneVerificationThrottled = true;'));
      expect(source, contains('phone_verification_throttled'));
      expect(source, contains('Yeni SMS isteği bu oturumda durduruldu.'));

      expect(source, isNot(contains('Timer(')));
      expect(source, isNot(contains('Future.delayed(')));
    },
  );

  test(
    'stale phone callbacks cannot overwrite a terminal Google-link result',
    () {
      final source = File(
        'lib/screens/auth/login_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('final googlePhoneLinkRequest = _googlePhoneLinkPending;'),
      );

      expect(
        RegExp(
          r'googlePhoneLinkRequest\s*&&\s*!_googlePhoneLinkPending',
        ).allMatches(source).length,
        greaterThanOrEqualTo(4),
      );

      final abortStart = source.indexOf('Future<void> _abortGooglePhoneLink()');
      final googleStart = source.indexOf('Future<void> _startGoogleSignIn()');

      expect(abortStart, greaterThanOrEqualTo(0));
      expect(googleStart, greaterThan(abortStart));

      final abort = source.substring(abortStart, googleStart);

      expect(abort, contains('_verificationId = null;'));
      expect(abort, contains('codeController.clear();'));
      expect(abort, contains('await _auth.signOut();'));
      expect(abort, contains('_googleSignInCoordinator.clearPendingLink();'));
    },
  );
}
