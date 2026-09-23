import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase/firebase_functions_registry.dart';

class RideVoiceCallCreateException implements Exception {
  const RideVoiceCallCreateException(this.code);

  final String code;
}

abstract interface class RideVoiceCallCreateCallableInvoker {
  Future<Object?> call(String callable, Map<String, dynamic> data);
}

class RideVoiceCallCreateService {
  RideVoiceCallCreateService({RideVoiceCallCreateCallableInvoker? invoker})
    : _invoker = invoker ?? _FirebaseRideVoiceCallCreateCallableInvoker();

  static const _safeCodes = <String>{
    'unauthenticated',
    'permission-denied',
    'failed-precondition',
    'invalid-argument',
    'not-found',
    'already-exists',
    'resource-exhausted',
    'unavailable',
    'internal',
  };

  final RideVoiceCallCreateCallableInvoker _invoker;

  Future<void> create({required String rideId}) async {
    final normalizedRideId = rideId.trim();
    if (normalizedRideId.isEmpty) {
      throw const RideVoiceCallCreateException('invalid-argument');
    }

    try {
      await _invoker.call(
        FirebaseFunctionsRegistry.createRideVoiceCall,
        <String, dynamic>{'rideId': normalizedRideId},
      );
    } on RideVoiceCallCreateException catch (error) {
      throw RideVoiceCallCreateException(_safeCode(error.code));
    } catch (_) {
      throw const RideVoiceCallCreateException('unavailable');
    }
  }

  static String _safeCode(String code) =>
      _safeCodes.contains(code) ? code : 'internal';
}

class _FirebaseRideVoiceCallCreateCallableInvoker
    implements RideVoiceCallCreateCallableInvoker {
  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    try {
      final result = await FirebaseFunctionsRegistry.client
          .httpsCallable(callable)
          .call(data);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw RideVoiceCallCreateException(error.code);
    }
  }
}
