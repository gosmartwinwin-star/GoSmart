import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseFunctionsRouting {
  const FirebaseFunctionsRouting({
    required this.projectId,
    required this.region,
    this.emulatorHost,
    this.emulatorPort,
  });

  final String projectId;
  final String region;
  final String? emulatorHost;
  final int? emulatorPort;

  bool get usesEmulator => emulatorHost != null && emulatorPort != null;

  static FirebaseFunctionsRouting resolve({
    required String projectId,
    String? emulatorHost,
    int? emulatorPort,
  }) {
    if ((emulatorHost == null) != (emulatorPort == null)) {
      throw ArgumentError('Functions emulator host ve port birlikte verilmeli.');
    }
    return FirebaseFunctionsRouting(
      projectId: projectId,
      region: FirebaseFunctionsRegistry.region,
      emulatorHost: emulatorHost,
      emulatorPort: emulatorPort,
    );
  }
}

class FirebaseFunctionsRegistry {
  static const region = 'europe-west1';
  static const getMyRideHistory = 'getMyRideHistory';
  static FirebaseFunctions? _client;
  static FirebaseFunctionsRouting? _routing;

  static FirebaseFunctions configure({
    required FirebaseApp app,
    String? emulatorHost,
    int? emulatorPort,
  }) {
    final routing = FirebaseFunctionsRouting.resolve(
      projectId: app.options.projectId,
      emulatorHost: emulatorHost,
      emulatorPort: emulatorPort,
    );
    final client = FirebaseFunctions.instanceFor(app: app, region: region);
    if (emulatorHost != null && emulatorPort != null) {
      client.useFunctionsEmulator(
        emulatorHost,
        emulatorPort,
        automaticHostMapping: false,
      );
    }
    _client = client;
    _routing = routing;
    return client;
  }

  static FirebaseFunctions get client {
    final value = _client;
    if (value == null) {
      throw StateError('Firebase Functions client henüz yapılandırılmadı.');
    }
    return value;
  }

  static FirebaseFunctionsRouting get routing {
    final value = _routing;
    if (value == null) {
      throw StateError('Firebase Functions routing henüz yapılandırılmadı.');
    }
    return value;
  }
}
