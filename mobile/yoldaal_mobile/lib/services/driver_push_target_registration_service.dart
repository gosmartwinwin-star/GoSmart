import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/firebase/firebase_functions_registry.dart';

enum DriverPushTargetPlatform {
  android('android'),
  ios('ios');

  const DriverPushTargetPlatform(this.wireValue);

  final String wireValue;
}

final class DriverPushTargetRegistrationResult {
  const DriverPushTargetRegistrationResult({
    required this.updatedAtMillis,
  });

  final int updatedAtMillis;
}

final class DriverPushTargetRegistrationException implements Exception {
  const DriverPushTargetRegistrationException({
    required this.code,
    this.reason,
  });

  final String code;
  final String? reason;
}

abstract interface class DriverPushTargetAuthSession {
  Future<void> requireAuthenticatedUser();
}

abstract interface class DriverPushInstallationIdSource {
  Future<String> getId();

  Stream<String> get onIdChange;
}

abstract interface class DriverPushTargetCallableInvoker {
  Future<Object?> call(Map<String, Object?> payload);
}

class FirebaseDriverPushTargetAuthSession implements DriverPushTargetAuthSession {
  FirebaseDriverPushTargetAuthSession({
    FirebaseAuth? auth,
  }) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Future<void> requireAuthenticatedUser() async {
    if (_auth.currentUser == null) {
      throw const DriverPushTargetRegistrationException(
        code: 'unauthenticated',
      );
    }
  }
}

class FirebaseDriverPushInstallationIdSource
    implements DriverPushInstallationIdSource {
  FirebaseDriverPushInstallationIdSource({
    FirebaseInstallations? installations,
  }) : _installations = installations ?? FirebaseInstallations.instance;

  final FirebaseInstallations _installations;

  @override
  Future<String> getId() => _installations.getId();

  @override
  Stream<String> get onIdChange => _installations.onIdChange;
}

class FirebaseDriverPushTargetCallableInvoker
    implements DriverPushTargetCallableInvoker {
  FirebaseDriverPushTargetCallableInvoker({
    FirebaseFunctions? functions,
  }) : _functions = functions ?? FirebaseFunctionsRegistry.client;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final callable = _functions.httpsCallable(
        FirebaseFunctionsRegistry.registerDriverPushTarget,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 35),
        ),
      );

      final result = await callable.call<Map<String, Object?>>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map && details['reason'] is String
          ? details['reason'] as String
          : null;

      throw DriverPushTargetRegistrationException(
        code: error.code,
        reason: reason,
      );
    }
  }
}

class DriverPushTargetRegistrationService {
  DriverPushTargetRegistrationService({
    DriverPushTargetAuthSession? authSession,
    DriverPushInstallationIdSource? installationIdSource,
    DriverPushTargetCallableInvoker? invoker,
  }) : _authSession =
           authSession ?? FirebaseDriverPushTargetAuthSession(),
       _installationIdSource =
           installationIdSource ?? FirebaseDriverPushInstallationIdSource(),
       _invoker = invoker ?? FirebaseDriverPushTargetCallableInvoker();

  final DriverPushTargetAuthSession _authSession;
  final DriverPushInstallationIdSource _installationIdSource;
  final DriverPushTargetCallableInvoker _invoker;

  Stream<String> get installationIdChanges => _installationIdSource.onIdChange;

  Future<DriverPushTargetRegistrationResult> registerCurrentInstallation({
    required DriverPushTargetPlatform platform,
  }) async {
    await _authSession.requireAuthenticatedUser();

    final fid = await _installationIdSource.getId();

    return _registerAuthenticated(
      fid: fid,
      platform: platform,
    );
  }

  Future<DriverPushTargetRegistrationResult> registerInstallationId({
    required String fid,
    required DriverPushTargetPlatform platform,
  }) async {
    await _authSession.requireAuthenticatedUser();

    return _registerAuthenticated(
      fid: fid,
      platform: platform,
    );
  }

  Future<DriverPushTargetRegistrationResult> _registerAuthenticated({
    required String fid,
    required DriverPushTargetPlatform platform,
  }) async {
    if (!_isCanonicalFid(fid)) {
      throw const FormatException(
        'Driver push installation ID is invalid.',
      );
    }

    final response = await _invoker.call({
      'fid': fid,
      'platform': platform.wireValue,
    });

    if (response is! Map ||
        response.length != 1 ||
        !response.containsKey('updatedAtMillis')) {
      throw const FormatException(
        'Driver push target response is invalid.',
      );
    }

    final updatedAtMillis = response['updatedAtMillis'];

    if (updatedAtMillis is! int) {
      throw const FormatException(
        'Driver push target response is invalid.',
      );
    }

    return DriverPushTargetRegistrationResult(
      updatedAtMillis: updatedAtMillis,
    );
  }

  static bool _isCanonicalFid(String value) {
    if (value.length < 8 || value.length > 512) {
      return false;
    }

    if (value.trim() != value) {
      return false;
    }

    return !RegExp(r'\s').hasMatch(value);
  }
}
