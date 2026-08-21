import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:gosmart_mobile/firebase_emulator_config.dart';

void main() {
  test('emulator mode is off when not requested', () {
    expect(
      FirebaseEmulatorConfig.resolve(
        requested: false,
        debugMode: true,
        platform: EmulatorPlatform.android,
      ),
      isNull,
    );
  });

  test('debug emulator uses demo project and Android host', () {
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

  test('other local platforms use loopback emulator host', () {
    final config = FirebaseEmulatorConfig.resolve(
      requested: true,
      debugMode: true,
      platform: EmulatorPlatform.local,
    )!;

    expect(config.host, '127.0.0.1');
  });

  test('emulator port contract remains fixed', () {
    expect(FirebaseEmulatorConfig.authPort, 9099);
    expect(FirebaseEmulatorConfig.functionsPort, 5001);
    expect(FirebaseEmulatorConfig.firestorePort, 8080);
    expect(FirebaseEmulatorConfig.storagePort, 9199);
  });

  test('non-debug emulator request fails closed', () {
    expect(
      () => FirebaseEmulatorConfig.resolve(
        requested: true,
        debugMode: false,
        platform: EmulatorPlatform.local,
      ),
      throwsStateError,
    );
  });

  test('production plan selects exact production options', () {
    const production = FirebaseOptions(
      apiKey: 'production-key',
      appId: 'production-app',
      messagingSenderId: 'production-sender',
      projectId: 'gosmart-fd8f6',
    );

    const sandbox = FirebaseOptions(
      apiKey: 'sandbox-key',
      appId: 'sandbox-app',
      messagingSenderId: 'sandbox-sender',
      projectId: 'gosmart-sandbox-fd8f6',
    );

    final plan = FirebaseBootstrapPlan.resolve(
      emulatorRequested: false,
      sandboxRequested: false,
      debugMode: false,
      platform: EmulatorPlatform.android,
      productionOptions: production,
      sandboxOptions: sandbox,
    );

    expect(plan.options, same(production));
    expect(plan.emulator, isNull);
  });

  test('emulator plan selects demo options only', () {
    const production = FirebaseOptions(
      apiKey: 'production-key',
      appId: 'production-app',
      messagingSenderId: 'production-sender',
      projectId: 'gosmart-fd8f6',
    );

    const sandbox = FirebaseOptions(
      apiKey: 'sandbox-key',
      appId: 'sandbox-app',
      messagingSenderId: 'sandbox-sender',
      projectId: 'gosmart-sandbox-fd8f6',
    );

    final plan = FirebaseBootstrapPlan.resolve(
      emulatorRequested: true,
      sandboxRequested: false,
      debugMode: true,
      platform: EmulatorPlatform.android,
      productionOptions: production,
      sandboxOptions: sandbox,
    );

    expect(plan.options.projectId, FirebaseEmulatorConfig.projectId);

    expect(plan.options.projectId, isNot(production.projectId));

    expect(plan.options.projectId, isNot(sandbox.projectId));

    expect(plan.emulator, isNotNull);
  });

  test('sandbox plan selects exact sandbox options without emulator', () {
    const production = FirebaseOptions(
      apiKey: 'production-key',
      appId: 'production-app',
      messagingSenderId: 'production-sender',
      projectId: 'gosmart-fd8f6',
    );

    const sandbox = FirebaseOptions(
      apiKey: 'sandbox-key',
      appId: 'sandbox-app',
      messagingSenderId: 'sandbox-sender',
      projectId: 'gosmart-sandbox-fd8f6',
    );

    final plan = FirebaseBootstrapPlan.resolve(
      emulatorRequested: false,
      sandboxRequested: true,
      debugMode: false,
      platform: EmulatorPlatform.android,
      productionOptions: production,
      sandboxOptions: sandbox,
    );

    expect(plan.options, same(sandbox));
    expect(plan.options.projectId, 'gosmart-sandbox-fd8f6');
    expect(plan.options.projectId, isNot(production.projectId));
    expect(plan.emulator, isNull);
  });

  test('emulator plus sandbox request fails closed', () {
    const production = FirebaseOptions(
      apiKey: 'production-key',
      appId: 'production-app',
      messagingSenderId: 'production-sender',
      projectId: 'gosmart-fd8f6',
    );

    const sandbox = FirebaseOptions(
      apiKey: 'sandbox-key',
      appId: 'sandbox-app',
      messagingSenderId: 'sandbox-sender',
      projectId: 'gosmart-sandbox-fd8f6',
    );

    expect(
      () => FirebaseBootstrapPlan.resolve(
        emulatorRequested: true,
        sandboxRequested: true,
        debugMode: true,
        platform: EmulatorPlatform.android,
        productionOptions: production,
        sandboxOptions: sandbox,
      ),
      throwsStateError,
    );
  });

  test('sandbox request without options fails closed', () {
    const production = FirebaseOptions(
      apiKey: 'production-key',
      appId: 'production-app',
      messagingSenderId: 'production-sender',
      projectId: 'gosmart-fd8f6',
    );

    expect(
      () => FirebaseBootstrapPlan.resolve(
        emulatorRequested: false,
        sandboxRequested: true,
        debugMode: true,
        platform: EmulatorPlatform.android,
        productionOptions: production,
      ),
      throwsStateError,
    );
  });

  test('main manifest removes native Firebase DEFAULT auto-init', () {
    final mainManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      mainManifest,
      contains('com.google.firebase.provider.FirebaseInitProvider'),
    );

    expect(mainManifest, contains('tools:node="remove"'));

    expect(mainManifest, isNot(contains('usesCleartextTraffic')));
  });

  test('only debug manifest permits cleartext emulator traffic', () {
    final debugManifest = File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsStringSync();

    final profileManifest = File(
      'android/app/src/profile/AndroidManifest.xml',
    ).readAsStringSync();

    final mainManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(debugManifest, contains('android:usesCleartextTraffic="true"'));

    expect(profileManifest, isNot(contains('usesCleartextTraffic')));

    expect(mainManifest, isNot(contains('usesCleartextTraffic')));
  });

  test('emulator Functions routing uses Android host port and region', () {
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

  test('production Functions routing contains no emulator endpoint', () {
    final routing = FirebaseFunctionsRouting.resolve(
      projectId: 'gosmart-fd8f6',
    );

    expect(routing.region, 'europe-west1');
    expect(routing.usesEmulator, isFalse);
  });

  test('sandbox Functions routing contains no emulator endpoint', () {
    final routing = FirebaseFunctionsRouting.resolve(
      projectId: 'gosmart-sandbox-fd8f6',
    );

    expect(routing.projectId, 'gosmart-sandbox-fd8f6');
    expect(routing.region, 'europe-west1');
    expect(routing.usesEmulator, isFalse);
  });
}
