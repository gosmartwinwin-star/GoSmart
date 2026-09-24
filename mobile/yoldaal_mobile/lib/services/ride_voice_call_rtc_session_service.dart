import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase/firebase_functions_registry.dart';

typedef RideVoiceCallRtcNowMillis = int Function();

class RideVoiceCallRtcSession {
  const RideVoiceCallRtcSession({
    required this.appId,
    required this.channelName,
    required this.token,
    required this.rtcUid,
    required this.expiresAtMillis,
  });

  final String appId;
  final String channelName;
  final String token;
  final int rtcUid;
  final int expiresAtMillis;
}

class RideVoiceCallRtcSessionException implements Exception {
  const RideVoiceCallRtcSessionException(this.code);

  final String code;
}

abstract interface class RideVoiceCallRtcSessionCallableInvoker {
  Future<Object?> call(String callable, Map<String, dynamic> data);
}

abstract interface class RideVoiceCallRtcSessionGateway {
  Future<RideVoiceCallRtcSession> getActiveSession();
}

class RideVoiceCallRtcSessionService implements RideVoiceCallRtcSessionGateway {
  RideVoiceCallRtcSessionService({
    RideVoiceCallRtcSessionCallableInvoker? invoker,
    RideVoiceCallRtcNowMillis? nowMillis,
  }) : _invoker = invoker ?? _FirebaseRideVoiceCallRtcSessionCallableInvoker(),
       _nowMillis = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const _rootKeys = <String>{
    'appId',
    'channelName',
    'token',
    'rtcUid',
    'expiresAtMillis',
  };

  static const _safeCodes = <String>{
    'unauthenticated',
    'permission-denied',
    'failed-precondition',
    'invalid-argument',
    'not-found',
    'resource-exhausted',
    'unavailable',
    'internal',
    'invalid-response',
  };

  static final RegExp _appIdPattern = RegExp(r'^[0-9a-fA-F]{32}$');
  static final RegExp _channelPattern = RegExp(r'^rvc_[0-9a-f]{32}$');

  final RideVoiceCallRtcSessionCallableInvoker _invoker;
  final RideVoiceCallRtcNowMillis _nowMillis;

  @override
  Future<RideVoiceCallRtcSession> getActiveSession() async {
    Object? rawResponse;

    try {
      rawResponse = await _invoker.call(
        FirebaseFunctionsRegistry.getMyActiveRideVoiceRtcSession,
        const <String, dynamic>{},
      );
    } on RideVoiceCallRtcSessionException catch (error) {
      throw RideVoiceCallRtcSessionException(_safeCode(error.code));
    } catch (_) {
      throw const RideVoiceCallRtcSessionException('unavailable');
    }

    try {
      if (rawResponse is! Map) {
        throw const FormatException('Invalid RTC session response.');
      }

      final response = Map<String, dynamic>.from(rawResponse);
      if (!_hasExactKeys(response, _rootKeys)) {
        throw const FormatException('Invalid RTC session response.');
      }

      final appId = _appId(response['appId']);
      final channelName = _channelName(response['channelName']);
      final token = _nonEmptyString(response['token']);
      final rtcUid = _rtcUid(response['rtcUid']);
      final expiresAtMillis = _positiveInt(response['expiresAtMillis']);

      if (appId == null ||
          channelName == null ||
          token == null ||
          rtcUid == null ||
          expiresAtMillis == null ||
          expiresAtMillis <= _nowMillis()) {
        throw const FormatException('Invalid RTC session response.');
      }

      return RideVoiceCallRtcSession(
        appId: appId,
        channelName: channelName,
        token: token,
        rtcUid: rtcUid,
        expiresAtMillis: expiresAtMillis,
      );
    } catch (_) {
      throw const RideVoiceCallRtcSessionException('invalid-response');
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

  static String? _appId(Object? value) {
    if (value is! String || !_appIdPattern.hasMatch(value)) {
      return null;
    }
    return value;
  }

  static String? _channelName(Object? value) {
    if (value is! String || !_channelPattern.hasMatch(value)) {
      return null;
    }
    return value;
  }

  static int? _rtcUid(Object? value) {
    if (value is! int || (value != 1 && value != 2)) {
      return null;
    }
    return value;
  }

  static int? _positiveInt(Object? value) =>
      value is int && value > 0 ? value : null;

  static String _safeCode(String code) =>
      _safeCodes.contains(code) ? code : 'internal';
}

class _FirebaseRideVoiceCallRtcSessionCallableInvoker
    implements RideVoiceCallRtcSessionCallableInvoker {
  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    try {
      final result = await FirebaseFunctionsRegistry.client
          .httpsCallable(callable)
          .call<Map<String, dynamic>>(data);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw RideVoiceCallRtcSessionException(error.code);
    }
  }
}
