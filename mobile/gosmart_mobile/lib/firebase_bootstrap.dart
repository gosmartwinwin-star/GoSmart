import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'core/firebase/firebase_functions_registry.dart';
import 'firebase_emulator_config.dart';
import 'firebase_options.dart';

Future<void> initializeFirebase() async {
  final plan = FirebaseBootstrapPlan.resolve(
    requested: firebaseEmulatorsRequested,
    debugMode: kDebugMode,
    platform: currentEmulatorPlatform,
    productionOptions: DefaultFirebaseOptions.currentPlatform,
  );
  await Firebase.initializeApp(options: plan.options);
  if (kDebugMode) {
    debugPrint('Firebase çalışma projesi: ${Firebase.app().options.projectId}');
    debugPrint(
      'Firebase seçenek projesi: '
      '${Firebase.app().options.projectId}',
    );
  }
  final emulator = plan.emulator;
  FirebaseFunctionsRegistry.configure(
    app: Firebase.app(),
    emulatorHost: emulator?.host,
    emulatorPort: emulator == null
        ? null
        : FirebaseEmulatorConfig.functionsPort,
  );
  if (emulator == null) return;

  await FirebaseAuth.instance.useAuthEmulator(
    emulator.host,
    FirebaseEmulatorConfig.authPort,
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    emulator.host,
    FirebaseEmulatorConfig.firestorePort,
  );
  await FirebaseStorage.instance.useStorageEmulator(
    emulator.host,
    FirebaseEmulatorConfig.storagePort,
  );
}
