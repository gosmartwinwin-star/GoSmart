import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/firebase_emulator_config.dart';
import 'package:gosmart_mobile/core/firebase/firebase_functions_registry.dart';

void main() {
  test('flag yokken emulator modu kapalıdır', () {
    expect(
      FirebaseEmulatorConfig.resolve(
        requested: false,
        debugMode: true,
        platform: EmulatorPlatform.android,
      ),
      isNull,
    );
  });

  test('debug flag demo options ve Android host seçer', () {
    final config = FirebaseEmulatorConfig.resolve(
      requested: true,
      debugMode: true,
      platform: EmulatorPlatform.android,
    )!;
    final demoOptions = FirebaseEmulatorConfig.demoOptions;
    expect(demoOptions.projectId, 'demo-gosmart');
    expect(demoOptions.apiKey, startsWith('AIza'));
    expect(demoOptions.apiKey.length, 39);
    expect(config.host, '10.0.2.2');
  });

  test('diğer yerel platformlar loopback host seçer', () {
    final config = FirebaseEmulatorConfig.resolve(
      requested: true,
      debugMode: true,
      platform: EmulatorPlatform.local,
    )!;
    expect(config.host, '127.0.0.1');
  });

  test('emulator port sözleşmesi sabittir', () {
    expect(FirebaseEmulatorConfig.authPort, 9099);
    expect(FirebaseEmulatorConfig.functionsPort, 5001);
    expect(FirebaseEmulatorConfig.firestorePort, 8080);
    expect(FirebaseEmulatorConfig.storagePort, 9199);
  });

  test('debug olmayan build flag kullanımını fail-closed reddeder', () {
    expect(
      () => FirebaseEmulatorConfig.resolve(
        requested: true,
        debugMode: false,
        platform: EmulatorPlatform.local,
      ),
      throwsStateError,
    );
  });

  test('production plan tam olarak production DEFAULT options seçer', () {
    const production = FirebaseOptions(
      apiKey: 'production-key',
      appId: 'production-app',
      messagingSenderId: 'production-sender',
      projectId: 'gosmart-fd8f6',
    );
    final plan = FirebaseBootstrapPlan.resolve(
      requested: false,
      debugMode: false,
      platform: EmulatorPlatform.android,
      productionOptions: production,
    );
    expect(plan.options, same(production));
    expect(plan.emulator, isNull);
  });

  test('emulator plan yalnız demo DEFAULT options seçer', () {
    const production = FirebaseOptions(
      apiKey: 'production-key',
      appId: 'production-app',
      messagingSenderId: 'production-sender',
      projectId: 'gosmart-fd8f6',
    );
    final plan = FirebaseBootstrapPlan.resolve(
      requested: true,
      debugMode: true,
      platform: EmulatorPlatform.android,
      productionOptions: production,
    );
    expect(plan.options.projectId, FirebaseEmulatorConfig.projectId);
    expect(plan.options.projectId, isNot(production.projectId));
    expect(plan.emulator, isNotNull);
  });

  test('main manifest native Firebase DEFAULT auto-init kaldırır', () {
    final mainManifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      mainManifest,
      contains('com.google.firebase.provider.FirebaseInitProvider'),
    );
    expect(mainManifest, contains('tools:node="remove"'));
    expect(mainManifest, isNot(contains('usesCleartextTraffic')));
  });

  test('yalnız debug manifest cleartext emulator trafiğine izin verir', () {
    final debugManifest = File('android/app/src/debug/AndroidManifest.xml')
        .readAsStringSync();
    final profileManifest = File('android/app/src/profile/AndroidManifest.xml')
        .readAsStringSync();
    final mainManifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(debugManifest, contains('android:usesCleartextTraffic="true"'));
    expect(profileManifest, isNot(contains('usesCleartextTraffic')));
    expect(mainManifest, isNot(contains('usesCleartextTraffic')));
  });

  test('emulator Functions routing Android host port ve region kullanır', () {
    final routing = FirebaseFunctionsRouting.resolve(
      projectId: FirebaseEmulatorConfig.projectId,
      emulatorHost: '10.0.2.2',
      emulatorPort: FirebaseEmulatorConfig.functionsPort,
    );
    expect(routing.projectId, 'demo-gosmart');
    expect(routing.region, 'europe-west1');
    expect(routing.emulatorHost, '10.0.2.2');
    expect(routing.emulatorPort, 5001);
    expect(routing.usesEmulator, isTrue);
  });

  test('production Functions routing emulator endpoint içermez', () {
    final routing = FirebaseFunctionsRouting.resolve(
      projectId: 'gosmart-fd8f6',
    );
    expect(routing.region, 'europe-west1');
    expect(routing.usesEmulator, isFalse);
  });
}
