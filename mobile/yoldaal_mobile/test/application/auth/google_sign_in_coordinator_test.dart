import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/auth/google_sign_in_coordinator.dart';

void main() {
  group('GoogleSignInCoordinator', () {
    test('linked Google account signs in directly', () async {
      var signInCalls = 0;
      var linkCalls = 0;

      final coordinator = GoogleSignInCoordinator(
        acquireIdToken: () async => 'google-token',
        resolveLinkState: (_) async => true,
        signInLinked: (token) async {
          expect(token, 'google-token');
          signInCalls++;
        },
        linkCurrentUser: (_) async {
          linkCalls++;
        },
      );

      final result = await coordinator.start();

      expect(result.disposition, GoogleSignInStartDisposition.signedIn);

      expect(signInCalls, 1);
      expect(linkCalls, 0);
      expect(coordinator.hasPendingLink, isFalse);
    });

    test('unlinked Google account requires phone verification', () async {
      var signInCalls = 0;

      final coordinator = GoogleSignInCoordinator(
        acquireIdToken: () async => 'google-token',
        resolveLinkState: (_) async => false,
        signInLinked: (_) async {
          signInCalls++;
        },
        linkCurrentUser: (_) async {},
      );

      final result = await coordinator.start();

      expect(
        result.disposition,
        GoogleSignInStartDisposition.phoneVerificationRequired,
      );

      expect(signInCalls, 0);
      expect(coordinator.hasPendingLink, isTrue);
    });

    test('phone canonical user receives pending Google link', () async {
      var linkedToken = '';

      final coordinator = GoogleSignInCoordinator(
        acquireIdToken: () async => 'google-token',
        resolveLinkState: (_) async => false,
        signInLinked: (_) async {},
        linkCurrentUser: (token) async {
          linkedToken = token;
        },
      );

      await coordinator.start();

      await coordinator.linkPendingAfterPhoneSignIn();

      expect(linkedToken, 'google-token');

      expect(coordinator.hasPendingLink, isFalse);
    });

    test('failed link keeps pending token for fail closed handling', () async {
      final coordinator = GoogleSignInCoordinator(
        acquireIdToken: () async => 'google-token',
        resolveLinkState: (_) async => false,
        signInLinked: (_) async {},
        linkCurrentUser: (_) async {
          throw const GoogleSignInFlowException('link_failed');
        },
      );

      await coordinator.start();

      await expectLater(
        coordinator.linkPendingAfterPhoneSignIn(),
        throwsA(isA<GoogleSignInFlowException>()),
      );

      expect(coordinator.hasPendingLink, isTrue);
    });

    test('missing pending link fails closed', () async {
      final coordinator = GoogleSignInCoordinator(
        acquireIdToken: () async => 'google-token',
        resolveLinkState: (_) async => true,
        signInLinked: (_) async {},
        linkCurrentUser: (_) async {},
      );

      await expectLater(
        coordinator.linkPendingAfterPhoneSignIn(),
        throwsA(
          isA<GoogleSignInFlowException>().having(
            (error) => error.code,
            'code',
            'missing_pending_google_link',
          ),
        ),
      );
    });

    test('explicit clear removes pending provider token', () async {
      final coordinator = GoogleSignInCoordinator(
        acquireIdToken: () async => 'google-token',
        resolveLinkState: (_) async => false,
        signInLinked: (_) async {},
        linkCurrentUser: (_) async {},
      );

      await coordinator.start();

      expect(coordinator.hasPendingLink, isTrue);

      coordinator.clearPendingLink();

      expect(coordinator.hasPendingLink, isFalse);
    });
  });
}
