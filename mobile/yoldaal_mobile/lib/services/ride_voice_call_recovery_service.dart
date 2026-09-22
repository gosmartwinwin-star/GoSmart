import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase/firebase_functions_registry.dart';

enum RideVoiceCallRecoveryState { ringing, accepted, connecting, active }

enum RideVoiceCallRecoveryRole { driver, passenger }

enum RideVoiceCallRecoverySide { caller, callee }

class RideVoiceCallRecoverySnapshot {
  const RideVoiceCallRecoverySnapshot({
    required this.rideId,
    required this.callId,
    required this.state,
    required this.role,
    required this.side,
  });

  final String rideId;
  final String callId;
  final RideVoiceCallRecoveryState state;
  final RideVoiceCallRecoveryRole role;
  final RideVoiceCallRecoverySide side;
}

class RideVoiceCallRecoveryException implements Exception {
  const RideVoiceCallRecoveryException(this.code);

  final String code;
}

abstract interface class RideVoiceCallRecoveryCallableInvoker {
  Future<Object?> call(String callable, Map<String, dynamic> data);
}

class RideVoiceCallRecoveryService {
  RideVoiceCallRecoveryService({RideVoiceCallRecoveryCallableInvoker? invoker})
    : _invoker = invoker ?? _FirebaseRideVoiceCallRecoveryCallableInvoker();

  static const _rootKeys = <String>{'activeCall'};
  static const _callKeys = <String>{
    'rideId',
    'callId',
    'state',
    'role',
    'side',
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
    'invalid-response',
  };

  static final RegExp _callIdPattern = RegExp(r'^rvc_[0-9a-f]{32}$');

  final RideVoiceCallRecoveryCallableInvoker _invoker;

  Future<RideVoiceCallRecoverySnapshot?> recover() async {
    Object? rawResponse;

    try {
      rawResponse = await _invoker.call(
        FirebaseFunctionsRegistry.getMyActiveRideVoiceCall,
        const <String, dynamic>{},
      );
    } on RideVoiceCallRecoveryException catch (error) {
      throw RideVoiceCallRecoveryException(_safeCode(error.code));
    } catch (_) {
      throw const RideVoiceCallRecoveryException('unavailable');
    }

    try {
      if (rawResponse is! Map) {
        throw const FormatException('Invalid Voice recovery response.');
      }

      final response = Map<String, dynamic>.from(rawResponse);

      if (!_hasExactKeys(response, _rootKeys)) {
        throw const FormatException('Invalid Voice recovery response.');
      }

      final rawCall = response['activeCall'];

      if (rawCall == null) {
        return null;
      }

      if (rawCall is! Map) {
        throw const FormatException('Invalid active Voice call.');
      }

      final call = Map<String, dynamic>.from(rawCall);

      if (!_hasExactKeys(call, _callKeys)) {
        throw const FormatException('Invalid active Voice call.');
      }

      final rideId = _nonEmptyString(call['rideId']);
      final callId = _voiceCallId(call['callId']);
      final state = _state(call['state']);
      final role = _role(call['role']);
      final side = _side(call['side']);

      if (rideId == null ||
          callId == null ||
          state == null ||
          role == null ||
          side == null) {
        throw const FormatException('Invalid active Voice call.');
      }

      return RideVoiceCallRecoverySnapshot(
        rideId: rideId,
        callId: callId,
        state: state,
        role: role,
        side: side,
      );
    } catch (_) {
      throw const RideVoiceCallRecoveryException('invalid-response');
    }
  }

  static bool _hasExactKeys(Map<String, dynamic> value, Set<String> expected) =>
      value.length == expected.length && value.keys.every(expected.contains);

  static String? _nonEmptyString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }

    return value;
  }

  static String? _voiceCallId(Object? value) {
    if (value is! String || !_callIdPattern.hasMatch(value)) {
      return null;
    }

    return value;
  }

  static RideVoiceCallRecoveryState? _state(Object? value) => switch (value) {
    'ringing' => RideVoiceCallRecoveryState.ringing,
    'accepted' => RideVoiceCallRecoveryState.accepted,
    'connecting' => RideVoiceCallRecoveryState.connecting,
    'active' => RideVoiceCallRecoveryState.active,
    _ => null,
  };

  static RideVoiceCallRecoveryRole? _role(Object? value) => switch (value) {
    'driver' => RideVoiceCallRecoveryRole.driver,
    'passenger' => RideVoiceCallRecoveryRole.passenger,
    _ => null,
  };

  static RideVoiceCallRecoverySide? _side(Object? value) => switch (value) {
    'caller' => RideVoiceCallRecoverySide.caller,
    'callee' => RideVoiceCallRecoverySide.callee,
    _ => null,
  };

  static String _safeCode(String code) =>
      _safeCodes.contains(code) ? code : 'unknown';
}

class _FirebaseRideVoiceCallRecoveryCallableInvoker
    implements RideVoiceCallRecoveryCallableInvoker {
  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    try {
      final result = await FirebaseFunctionsRegistry.client
          .httpsCallable(callable)
          .call<Map<String, dynamic>>(data);

      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw RideVoiceCallRecoveryException(error.code);
    }
  }
}
