import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase/firebase_functions_registry.dart';

class RideVoiceCallTransitionException implements Exception {
  const RideVoiceCallTransitionException(this.code);

  final String code;
}

abstract interface class RideVoiceCallTransitionCallableInvoker {
  Future<Object?> call(String callable, Map<String, dynamic> data);
}

class RideVoiceCallTransitionService {
  RideVoiceCallTransitionService({
    RideVoiceCallTransitionCallableInvoker? invoker,
  }) : _invoker = invoker ?? _FirebaseRideVoiceCallTransitionCallableInvoker();

  static const allowedTargetStates = <String>{
    'accepted',
    'declined',
    'cancelled',
    'ended',
  };

  static const _safeCodes = <String>{
    'unauthenticated',
    'permission-denied',
    'failed-precondition',
    'invalid-argument',
    'not-found',
    'already-exists',
    'unavailable',
    'internal',
  };

  static final RegExp _callIdPattern = RegExp(r'^rvc_[0-9a-f]{32}$');

  final RideVoiceCallTransitionCallableInvoker _invoker;

  Future<void> transition({
    required String rideId,
    required String callId,
    required String targetState,
  }) async {
    if (rideId.trim().isEmpty ||
        !_callIdPattern.hasMatch(callId) ||
        !allowedTargetStates.contains(targetState)) {
      throw const RideVoiceCallTransitionException('invalid-argument');
    }

    try {
      await _invoker.call(
        FirebaseFunctionsRegistry.transitionRideVoiceCall,
        <String, dynamic>{
          'rideId': rideId,
          'callId': callId,
          'toState': targetState,
        },
      );
    } on RideVoiceCallTransitionException catch (error) {
      throw RideVoiceCallTransitionException(_safeCode(error.code));
    } catch (_) {
      throw const RideVoiceCallTransitionException('unavailable');
    }
  }

  static String _safeCode(String code) =>
      _safeCodes.contains(code) ? code : 'internal';
}

class _FirebaseRideVoiceCallTransitionCallableInvoker
    implements RideVoiceCallTransitionCallableInvoker {
  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    try {
      final result = await FirebaseFunctionsRegistry.client
          .httpsCallable(callable)
          .call(data);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw RideVoiceCallTransitionException(error.code);
    }
  }
}
