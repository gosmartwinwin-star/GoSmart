import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/google_sign_in_service.dart';

void main() {
  group('Google link Firebase Auth safe diagnostic code', () {
    test('accepts bounded lowercase Firebase Auth code shape', () {
      for (final code in <String>[
        'unknown-error',
        'too-many-requests',
        'invalid-verification-id',
        'credential-already-in-use',
        'network-request-failed',
        'a',
        'a1-b2-c3',
      ]) {
        expect(
          sanitizeFirebaseAuthCodeForGoogleLinkDiagnostic(code),
          code,
          reason: code,
        );
      }

      final maxLengthCode = List<String>.filled(64, 'a').join();

      expect(
        sanitizeFirebaseAuthCodeForGoogleLinkDiagnostic(maxLengthCode),
        maxLengthCode,
      );
    });

    test('rejects empty oversized or unsafe diagnostic values', () {
      final oversized = List<String>.filled(65, 'a').join();

      for (final value in <String>[
        '',
        oversized,
        'UPPERCASE-CODE',
        'user@example.invalid',
        '+900000000000',
        'contains space',
        'contains_underscore',
        '../token',
        'code/value',
        'code:value',
        'code.value',
      ]) {
        expect(
          sanitizeFirebaseAuthCodeForGoogleLinkDiagnostic(value),
          isNull,
          reason: value,
        );
      }
    });

    test(
      'unmapped Firebase code logging preserves generic runtime failure mapping',
      () {
        final source = File(
          'lib/services/google_sign_in_service.dart',
        ).readAsStringSync();

        expect(
          source,
          contains('_debugLogUnmappedGoogleLinkFirebaseAuthCode(error.code);'),
        );

        expect(source, contains("safeCode = 'google_account_link_failed';"));

        final diagnostic = source.indexOf(
          '_debugLogUnmappedGoogleLinkFirebaseAuthCode(error.code);',
        );

        final genericMapping = source.indexOf(
          "safeCode = 'google_account_link_failed';",
          diagnostic,
        );

        expect(diagnostic, greaterThanOrEqualTo(0));
        expect(genericMapping, greaterThan(diagnostic));
      },
    );

    test('diagnostic logger cannot receive Firebase exception message', () {
      final source = File(
        'lib/services/google_sign_in_service.dart',
      ).readAsStringSync();

      expect(source, contains('Google link FirebaseAuth safe error code:'));

      expect(
        source,
        contains('_debugLogUnmappedGoogleLinkFirebaseAuthCode(error.code);'),
      );

      expect(
        source,
        isNot(
          contains('_debugLogUnmappedGoogleLinkFirebaseAuthCode(error.message'),
        ),
      );

      expect(
        source,
        isNot(contains('Google link FirebaseAuth safe error message:')),
      );
    });

    test(
      'persistent link operation remains the classified Firebase operation',
      () {
        final source = File(
          'lib/services/google_sign_in_service.dart',
        ).readAsStringSync();

        final start = source.indexOf(
          'Future<void> linkCurrentUser(String idToken) async',
        );

        final end = source.indexOf(
          'GoogleSignInCoordinator buildProductionGoogleSignInCoordinator',
          start,
        );

        expect(start, greaterThanOrEqualTo(0));
        expect(end, greaterThan(start));

        final method = source.substring(start, end);

        expect(
          method,
          contains('await user.linkWithCredential(_credential(idToken));'),
        );

        expect(method, isNot(contains('getIdToken(true)')));

        expect(method, contains('on FirebaseAuthException catch (error)'));

        expect(method, contains('throw GoogleSignInFlowException(safeCode);'));

        expect(method, isNot(contains('error.message')));
      },
    );
  });
}
