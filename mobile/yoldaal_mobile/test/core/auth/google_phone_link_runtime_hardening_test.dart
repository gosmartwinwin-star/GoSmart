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
      contains('final googleAutoVerification = _googlePhoneLinkPending;'),
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
}
