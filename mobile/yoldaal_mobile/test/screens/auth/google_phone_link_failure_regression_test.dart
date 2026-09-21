import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _slice(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startMarker');

  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, greaterThan(start), reason: 'Missing $endMarker');

  return source.substring(start, end);
}

void main() {
  const loginPath = 'lib/screens/auth/login_screen.dart';
  const googleServicePath = 'lib/services/google_sign_in_service.dart';
  const splashPath = 'lib/screens/splash/splash_screen.dart';

  test(
    'post-phone rollback releases the global auth gate before UI cleanup',
    () {
      final source = _read(loginPath);
      final abortBody = _slice(
        source,
        'Future<void> _abortGooglePhoneLink() async',
        'Future<void> _startGoogleSignIn() async',
      );

      final releaseIndex = abortBody.indexOf('authTransitionHold.release();');
      final clearIndex = abortBody.indexOf('codeController.clear();');
      final mountedGuardIndex = abortBody.indexOf('if (mounted) {');

      expect(releaseIndex, greaterThanOrEqualTo(0));
      expect(clearIndex, greaterThan(releaseIndex));
      expect(mountedGuardIndex, greaterThan(releaseIndex));
      expect(mountedGuardIndex, lessThan(clearIndex));

      expect(
        abortBody.indexOf('_googlePhoneLinkPending = false;'),
        lessThan(releaseIndex),
      );
      expect(
        abortBody.indexOf('_googleSignInCoordinator.clearPendingLink();'),
        lessThan(releaseIndex),
      );
    },
  );

  test(
    'successful phone-to-Google link is finalized without pre-success refresh',
    () {
      final source = _read(loginPath);
      final completeBody = _slice(
        source,
        'Future<void> _completeSignIn(PhoneAuthCredential credential) async',
        'Future<void> _abortGooglePhoneLink() async',
      );

      final linkIndex = completeBody.indexOf(
        'await _googleSignInCoordinator.linkPendingAfterPhoneSignIn();',
      );
      final pendingClearIndex = completeBody.indexOf(
        '_googlePhoneLinkPending = false;',
        linkIndex,
      );
      final releaseIndex = completeBody.indexOf(
        'authTransitionHold.release();',
        linkIndex,
      );
      final successMarkerIndex = completeBody.indexOf(
        "_recordGooglePhoneLinkRuntimeState('link_succeeded');",
        linkIndex,
      );

      expect(linkIndex, greaterThanOrEqualTo(0));
      expect(pendingClearIndex, greaterThan(linkIndex));
      expect(releaseIndex, greaterThan(pendingClearIndex));
      expect(successMarkerIndex, greaterThan(releaseIndex));

      expect(
        completeBody.contains('await user.getIdToken(true);'),
        isFalse,
        reason:
            'A token refresh after a persisted link must not be able to '
            'reclassify that link as failed.',
      );
    },
  );

  test(
    'linkCurrentUser classifies only the link operation as link failure',
    () {
      final source = _read(googleServicePath);
      final linkBody = _slice(
        source,
        'Future<void> linkCurrentUser(String idToken) async',
        'GoogleSignInCoordinator buildProductionGoogleSignInCoordinator',
      );

      expect(
        linkBody.contains(
          'await user.linkWithCredential(_credential(idToken));',
        ),
        isTrue,
      );

      expect(
        linkBody.contains('await user.getIdToken(true);'),
        isFalse,
        reason:
            'Post-link token refresh must not share the link failure catch.',
      );
    },
  );

  test(
    'authenticated splash remains the authoritative landing token refresh',
    () {
      final source = _read(splashPath);

      expect(source.contains('await user.getIdToken(true);'), isTrue);

      expect(source.contains('AuthenticatedLandingResolver('), isTrue);
    },
  );
}
