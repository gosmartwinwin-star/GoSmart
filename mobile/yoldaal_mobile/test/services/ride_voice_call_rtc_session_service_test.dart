import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_rtc_session_service.dart';

void main() {
  const expiresAt = 2_000_000;

  Map<String, dynamic> valid() => <String, dynamic>{
    'appId': '0123456789abcdef0123456789abcdef',
    'channelName': 'rvc_0123456789abcdef0123456789abcdef',
    'token': 'server-token',
    'rtcUid': 1,
    'expiresAtMillis': expiresAt,
  };

  test('uses exact empty payload and parses strict RTC DTO', () async {
    final invoker = _FakeInvoker(result: valid());
    final service = RideVoiceCallRtcSessionService(
      invoker: invoker,
      nowMillis: () => 1_000_000,
    );

    final session = await service.getActiveSession();

    expect(invoker.callable, 'getMyActiveRideVoiceRtcSession');
    expect(invoker.data, isEmpty);
    expect(session.appId, '0123456789abcdef0123456789abcdef');
    expect(session.channelName, 'rvc_0123456789abcdef0123456789abcdef');
    expect(session.token, 'server-token');
    expect(session.rtcUid, 1);
    expect(session.expiresAtMillis, expiresAt);
  });

  test('expanded response fails closed', () async {
    final response = valid()..['rideId'] = 'forbidden';
    final service = RideVoiceCallRtcSessionService(
      invoker: _FakeInvoker(result: response),
      nowMillis: () => 1_000_000,
    );

    await expectLater(
      service.getActiveSession(),
      throwsA(
        isA<RideVoiceCallRtcSessionException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  test('invalid channel uid or expired token data fails closed', () async {
    for (final response in <Map<String, dynamic>>[
      valid()..['channelName'] = 'ride-secret',
      valid()..['rtcUid'] = 3,
      valid()..['expiresAtMillis'] = 999_999,
    ]) {
      final service = RideVoiceCallRtcSessionService(
        invoker: _FakeInvoker(result: response),
        nowMillis: () => 1_000_000,
      );

      await expectLater(
        service.getActiveSession(),
        throwsA(
          isA<RideVoiceCallRtcSessionException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    }
  });

  test('transport errors are reduced to bounded codes', () async {
    final service = RideVoiceCallRtcSessionService(
      invoker: _FakeInvoker(error: StateError('raw transport secret')),
      nowMillis: () => 1_000_000,
    );

    await expectLater(
      service.getActiveSession(),
      throwsA(
        isA<RideVoiceCallRtcSessionException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });
}

class _FakeInvoker implements RideVoiceCallRtcSessionCallableInvoker {
  _FakeInvoker({this.result, this.error});

  final Object? result;
  final Object? error;

  String? callable;
  Map<String, dynamic>? data;

  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    this.callable = callable;
    this.data = Map<String, dynamic>.from(data);

    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }

    return result;
  }
}
