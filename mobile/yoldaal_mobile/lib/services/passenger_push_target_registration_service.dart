import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../core/firebase/firebase_functions_registry.dart';

enum PassengerPushTargetPlatform {
  android('android'),
  ios('ios');

  const PassengerPushTargetPlatform(this.wireValue);

  final String wireValue;
}

PassengerPushTargetPlatform? resolvePassengerPushTargetPlatform() {
  if (kIsWeb) {
    return null;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => PassengerPushTargetPlatform.android,
    TargetPlatform.iOS => PassengerPushTargetPlatform.ios,
    _ => null,
  };
}

final class PassengerPushTargetRegistrationResult {
  const PassengerPushTargetRegistrationResult({required this.updatedAtMillis});

  final int updatedAtMillis;
}

final class PassengerPushTargetRegistrationException implements Exception {
  const PassengerPushTargetRegistrationException({
    required this.code,
    this.reason,
  });

  final String code;
  final String? reason;
}

abstract interface class PassengerPushTargetAuthSession {
  Future<void> requireAuthenticatedUser();
}

abstract interface class PassengerPushInstallationIdSource {
  Future<String> getId();

  Stream<String> get onIdChange;
}

abstract interface class PassengerPushTargetCallableInvoker {
  Future<Object?> call(Map<String, Object?> payload);
}

class FirebasePassengerPushTargetAuthSession
    implements PassengerPushTargetAuthSession {
  FirebasePassengerPushTargetAuthSession({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Future<void> requireAuthenticatedUser() async {
    if (_auth.currentUser == null) {
      throw const PassengerPushTargetRegistrationException(
        code: 'unauthenticated',
      );
    }
  }
}

class FirebasePassengerPushInstallationIdSource
    implements PassengerPushInstallationIdSource {
  FirebasePassengerPushInstallationIdSource({
    FirebaseInstallations? installations,
  }) : _installations = installations ?? FirebaseInstallations.instance;

  final FirebaseInstallations _installations;

  @override
  Future<String> getId() => _installations.getId();

  @override
  Stream<String> get onIdChange => _installations.onIdChange;
}

class FirebasePassengerPushTargetCallableInvoker
    implements PassengerPushTargetCallableInvoker {
  FirebasePassengerPushTargetCallableInvoker({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctionsRegistry.client;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final callable = _functions.httpsCallable(
        FirebaseFunctionsRegistry.registerPassengerPushTarget,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
      );

      final result = await callable.call<Map<String, Object?>>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map && details['reason'] is String
          ? details['reason'] as String
          : null;

      throw PassengerPushTargetRegistrationException(
        code: error.code,
        reason: reason,
      );
    }
  }
}

class PassengerPushTargetRegistrationService {
  PassengerPushTargetRegistrationService({
    PassengerPushTargetAuthSession? authSession,
    PassengerPushInstallationIdSource? installationIdSource,
    PassengerPushTargetCallableInvoker? invoker,
  }) : _authSession = authSession ?? FirebasePassengerPushTargetAuthSession(),
       _installationIdSource =
           installationIdSource ?? FirebasePassengerPushInstallationIdSource(),
       _invoker = invoker ?? FirebasePassengerPushTargetCallableInvoker();

  final PassengerPushTargetAuthSession _authSession;
  final PassengerPushInstallationIdSource _installationIdSource;
  final PassengerPushTargetCallableInvoker _invoker;

  Stream<String> get installationIdChanges => _installationIdSource.onIdChange;

  Future<PassengerPushTargetRegistrationResult> registerCurrentInstallation({
    required PassengerPushTargetPlatform platform,
  }) async {
    await _authSession.requireAuthenticatedUser();

    final fid = await _installationIdSource.getId();

    return _registerAuthenticated(fid: fid, platform: platform);
  }

  Future<PassengerPushTargetRegistrationResult> registerInstallationId({
    required String fid,
    required PassengerPushTargetPlatform platform,
  }) async {
    await _authSession.requireAuthenticatedUser();

    return _registerAuthenticated(fid: fid, platform: platform);
  }

  Future<PassengerPushTargetRegistrationResult> _registerAuthenticated({
    required String fid,
    required PassengerPushTargetPlatform platform,
  }) async {
    if (!_isCanonicalFid(fid)) {
      throw const FormatException('Passenger push installation ID is invalid.');
    }

    final response = await _invoker.call({
      'fid': fid,
      'platform': platform.wireValue,
    });

    if (response is! Map ||
        response.length != 1 ||
        !response.containsKey('updatedAtMillis')) {
      throw const FormatException('Passenger push target response is invalid.');
    }

    final updatedAtMillis = response['updatedAtMillis'];

    if (updatedAtMillis is! int) {
      throw const FormatException('Passenger push target response is invalid.');
    }

    return PassengerPushTargetRegistrationResult(
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
