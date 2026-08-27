import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../application/driver/driver_live_presence_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import '../domain/return_route/geo_coordinate.dart';

abstract interface class DriverLivePresenceAuthSession {
  Future<void> requireAuthenticatedUser();
}

abstract interface class DriverLivePresenceCallableInvoker {
  Future<Object?> call(Map<String, Object?> payload);
}

class FirebaseDriverLivePresenceAuthSession
    implements DriverLivePresenceAuthSession {
  final FirebaseAuth _auth;

  FirebaseDriverLivePresenceAuthSession({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  @override
  Future<void> requireAuthenticatedUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const DriverLivePresencePublishException(
        code: 'unauthenticated',
      );
    }

    try {
      await user.getIdToken(true);
    } on FirebaseAuthException {
      throw const DriverLivePresencePublishException(
        code: 'unauthenticated',
      );
    }
  }
}

class FirebaseDriverLivePresenceCallableInvoker
    implements DriverLivePresenceCallableInvoker {
  final FirebaseFunctions _functions;

  FirebaseDriverLivePresenceCallableInvoker({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctionsRegistry.client;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final callable = _functions.httpsCallable(
        'publishDriverLiveLocation',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
      );
      final result = await callable.call<Map<String, Object?>>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map && details['reason'] is String
          ? details['reason'] as String
          : null;

      throw DriverLivePresencePublishException(
        code: error.code,
        reason: reason,
      );
    }
  }
}

class PublishDriverLiveLocationService implements DriverLivePresenceGateway {
  final DriverLivePresenceAuthSession _authSession;
  final DriverLivePresenceCallableInvoker _invoker;

  PublishDriverLiveLocationService({
    DriverLivePresenceAuthSession? authSession,
    DriverLivePresenceCallableInvoker? invoker,
  }) : _authSession =
           authSession ?? FirebaseDriverLivePresenceAuthSession(),
       _invoker = invoker ?? FirebaseDriverLivePresenceCallableInvoker();

  @override
  Future<DriverLivePresencePublishResult> publish({
    required GeoCoordinate location,
  }) async {
    await _authSession.requireAuthenticatedUser();

    final response = await _invoker.call({
      'latitude': location.latitude,
      'longitude': location.longitude,
    });

    if (response is! Map ||
        response.length != 1 ||
        !response.containsKey('updatedAtMillis')) {
      throw const FormatException(
        'Driver live presence response is invalid.',
      );
    }

    final updatedAtMillis = response['updatedAtMillis'];
    if (updatedAtMillis is! int) {
      throw const FormatException(
        'Driver live presence response is invalid.',
      );
    }

    return DriverLivePresencePublishResult(
      updatedAtMillis: updatedAtMillis,
    );
  }
}
