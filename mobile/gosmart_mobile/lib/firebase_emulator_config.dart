import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

const bool firebaseEmulatorsRequested = bool.fromEnvironment(
  'GOSMART_USE_FIREBASE_EMULATORS',
);

const bool firebaseSandboxRequested = bool.fromEnvironment(
  'GOSMART_USE_FIREBASE_SANDBOX',
);

enum EmulatorPlatform { android, local }

class FirebaseEmulatorConfig {
  static const projectId = 'demo-gosmart';
  static const authPort = 9099;
  static const functionsPort = 5001;
  static const firestorePort = 8080;
  static const storagePort = 9199;

  const FirebaseEmulatorConfig._({required this.host});

  final String host;

  static FirebaseEmulatorConfig? resolve({
    required bool requested,
    required bool debugMode,
    required EmulatorPlatform platform,
  }) {
    if (!requested) return null;

    if (!debugMode) {
      throw StateError(
        'Firebase Emulator mode is allowed only in debug builds.',
      );
    }

    return FirebaseEmulatorConfig._(
      host: platform == EmulatorPlatform.android ? '10.0.2.2' : '127.0.0.1',
    );
  }

  static FirebaseOptions get demoOptions => const FirebaseOptions(
    apiKey: 'AIza00000000000000000000000000000000000',
    appId: '1:123456789012:web:demo-gosmart',
    messagingSenderId: '123456789012',
    projectId: projectId,
    authDomain: 'demo-gosmart.firebaseapp.com',
    storageBucket: 'demo-gosmart.appspot.com',
  );
}

class FirebaseBootstrapPlan {
  const FirebaseBootstrapPlan({required this.options, this.emulator});

  final FirebaseOptions options;
  final FirebaseEmulatorConfig? emulator;

  static FirebaseBootstrapPlan resolve({
    required bool emulatorRequested,
    required bool sandboxRequested,
    required bool debugMode,
    required EmulatorPlatform platform,
    required FirebaseOptions productionOptions,
    FirebaseOptions? sandboxOptions,
  }) {
    if (emulatorRequested && sandboxRequested) {
      throw StateError(
        'Firebase emulator and sandbox modes cannot be requested together.',
      );
    }

    if (sandboxRequested && sandboxOptions == null) {
      throw StateError(
        'Firebase sandbox mode requires explicit sandbox options.',
      );
    }

    final emulator = FirebaseEmulatorConfig.resolve(
      requested: emulatorRequested,
      debugMode: debugMode,
      platform: platform,
    );

    if (emulator != null) {
      return FirebaseBootstrapPlan(
        options: FirebaseEmulatorConfig.demoOptions,
        emulator: emulator,
      );
    }

    if (sandboxRequested) {
      return FirebaseBootstrapPlan(options: sandboxOptions!);
    }

    return FirebaseBootstrapPlan(options: productionOptions);
  }
}

EmulatorPlatform get currentEmulatorPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? EmulatorPlatform.android
    : EmulatorPlatform.local;
