import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String bootstrapSource;
  late String functionsIndexSource;
  late String pubspecSource;

  setUpAll(() {
    bootstrapSource = File('lib/firebase_bootstrap.dart').readAsStringSync();
    functionsIndexSource = File('functions/src/index.ts').readAsStringSync();
    pubspecSource = File('pubspec.yaml').readAsStringSync();
  });

  test(
    'App Check activates after Firebase core and before Functions registry',
    () {
      final firebaseInit = bootstrapSource.indexOf(
        'await Firebase.initializeApp(options: plan.options);',
      );
      final appCheck = bootstrapSource.indexOf(
        'await FirebaseAppCheck.instance.activate(',
      );
      final functionsRegistry = bootstrapSource.indexOf(
        'FirebaseFunctionsRegistry.configure(',
      );

      expect(firebaseInit, greaterThanOrEqualTo(0));
      expect(appCheck, greaterThan(firebaseInit));
      expect(functionsRegistry, greaterThan(appCheck));
    },
  );

  test(
    'App Check uses debug providers only for debug builds and attestation otherwise',
    () {
      expect(
        bootstrapSource.contains(
          "import 'package:firebase_app_check/firebase_app_check.dart';",
        ),
        isTrue,
      );
      expect(bootstrapSource.contains('providerAndroid: kDebugMode'), isTrue);
      expect(bootstrapSource.contains('AndroidDebugProvider()'), isTrue);
      expect(
        bootstrapSource.contains('AndroidPlayIntegrityProvider()'),
        isTrue,
      );
      expect(bootstrapSource.contains('providerApple: kDebugMode'), isTrue);
      expect(bootstrapSource.contains('AppleDebugProvider()'), isTrue);
      expect(
        bootstrapSource.contains(
          'AppleAppAttestWithDeviceCheckFallbackProvider()',
        ),
        isTrue,
      );
      expect(bootstrapSource.contains('!kIsWeb'), isTrue);
    },
  );

  test('firebase_app_check dependency is pinned to the authorized release', () {
    expect(
      RegExp(
        r'^\s*firebase_app_check\s*:\s*\^?0\.4\.8\s*$',
        multiLine: true,
      ).hasMatch(pubspecSource),
      isTrue,
    );
  });

  test(
    'Google resolver, Voice and account deletion callables enforce App Check without token consumption',
    () {
      const resolverMarker =
          'export const resolveGoogleSignInLinkState = onCall(';
      const requestDeletionMarker =
          'export const requestAccountDeletion = onCall(';
      const requestDeletionNextMarker =
          'export const getMyRideMatchOffers = onCall(';
      const executeDeletionMarker =
          'export const executeAccountDeletion = onCall(';

      final resolverStart = functionsIndexSource.indexOf(resolverMarker);
      final requestDeletionStart = functionsIndexSource.indexOf(
        requestDeletionMarker,
      );
      final requestDeletionEnd = functionsIndexSource.indexOf(
        requestDeletionNextMarker,
      );
      final executeDeletionStart = functionsIndexSource.indexOf(
        executeDeletionMarker,
      );

      expect(resolverStart, greaterThanOrEqualTo(0));
      expect(requestDeletionStart, greaterThanOrEqualTo(0));
      expect(requestDeletionEnd, greaterThan(requestDeletionStart));
      expect(executeDeletionStart, greaterThanOrEqualTo(0));

      final resolverLength = functionsIndexSource.length - resolverStart;
      final resolverSource = functionsIndexSource.substring(
        resolverStart,
        resolverStart + (resolverLength < 1400 ? resolverLength : 1400),
      );
      final requestDeletionSource = functionsIndexSource.substring(
        requestDeletionStart,
        requestDeletionEnd,
      );
      final executeDeletionSource = functionsIndexSource.substring(
        executeDeletionStart,
      );

      expect(
        RegExp(r'enforceAppCheck\s*:\s*true').hasMatch(resolverSource),
        isTrue,
      );
      expect(
        RegExp(r'enforceAppCheck\s*:\s*true').hasMatch(requestDeletionSource),
        isTrue,
      );
      expect(
        RegExp(r'enforceAppCheck\s*:\s*true').hasMatch(executeDeletionSource),
        isTrue,
      );
      expect(
        RegExp(
          r'enforceAppCheck\s*:\s*true',
        ).allMatches(functionsIndexSource).length,
        7,
      );
      expect(
        RegExp(
          r'consumeAppCheckToken\s*:\s*true',
        ).hasMatch(functionsIndexSource),
        isFalse,
      );
    },
  );
}
