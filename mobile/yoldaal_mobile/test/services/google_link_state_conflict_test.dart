import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/auth/google_sign_in_coordinator.dart';
import 'package:yoldaal_mobile/services/google_sign_in_service.dart';

void main() {
  group('Google link-state conflict contract', () {
    test('ordinary one-key linked response remains backward compatible', () {
      expect(parseGoogleLinkStateResponse(<String, Object?>{'linked': true}), isTrue);
      expect(
        parseGoogleLinkStateResponse(<String, Object?>{'linked': false}),
        isFalse,
      );
    });

    test('bounded account conflict fails before phone-link disposition', () {
      expect(
        () => parseGoogleLinkStateResponse(
          <String, Object?>{
            'linked': false,
            'accountConflict': true,
          },
        ),
        throwsA(
          isA<GoogleSignInFlowException>().having(
            (error) => error.code,
            'code',
            'google_account_link_account_conflict',
          ),
        ),
      );
    });

    test('malformed expanded responses fail closed', () {
      final invalidValues = <Object?>[
        <String, Object?>{
          'linked': true,
          'accountConflict': true,
        },
        <String, Object?>{
          'linked': false,
          'accountConflict': false,
        },
        <String, Object?>{
          'linked': false,
          'accountConflict': true,
          'email': 'forbidden',
        },
      ];

      for (final value in invalidValues) {
        expect(
          () => parseGoogleLinkStateResponse(value),
          throwsA(
            isA<GoogleSignInFlowException>().having(
              (error) => error.code,
              'code',
              'invalid_link_state_response',
            ),
          ),
        );
      }
    });

    test('email-already-in-use uses explicit conflict fallback mapping', () {
      final source = File(
        'lib/services/google_sign_in_service.dart',
      ).readAsStringSync();

      expect(source, contains("case 'email-already-in-use':"));
      expect(
        source,
        contains("safeCode = 'google_account_link_account_conflict';"),
      );
    });

    test('resolver conflict occurs before pending phone-link state', () {
      final coordinator = File(
        'lib/application/auth/google_sign_in_coordinator.dart',
      ).readAsStringSync();

      final resolver = coordinator.indexOf(
        'final linked = await _resolveLinkState(idToken);',
      );
      final pending = coordinator.indexOf('_pendingIdToken = idToken;');

      expect(resolver, greaterThanOrEqualTo(0));
      expect(pending, greaterThan(resolver));

      final login = File(
        'lib/screens/auth/login_screen.dart',
      ).readAsStringSync();

      expect(
        login,
        contains('google_account_link_account_conflict'),
      );
    });
  });
}
