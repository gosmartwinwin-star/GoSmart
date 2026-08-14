import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

const bool firebaseEmulatorsRequested = bool.fromEnvironment(
  'GOSMART_USE_FIREBASE_EMULATORS',
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
        'Firebase Emulator modu yalnızca debug build içinde kullanılabilir.',
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
    required bool requested,
    required bool debugMode,
    required EmulatorPlatform platform,
    required FirebaseOptions productionOptions,
  }) {
    final emulator = FirebaseEmulatorConfig.resolve(
      requested: requested,
      debugMode: debugMode,
      platform: platform,
    );
    return FirebaseBootstrapPlan(
      options: emulator == null
          ? productionOptions
          : FirebaseEmulatorConfig.demoOptions,
      emulator: emulator,
    );
  }
}

EmulatorPlatform get currentEmulatorPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? EmulatorPlatform.android
    : EmulatorPlatform.local;
