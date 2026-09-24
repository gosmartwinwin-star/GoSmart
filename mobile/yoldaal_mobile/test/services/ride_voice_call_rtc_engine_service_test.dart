import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_rtc_engine_service.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_rtc_session_service.dart';

void main() {
  const session = RideVoiceCallRtcSession(
    appId: '0123456789abcdef0123456789abcdef',
    channelName: 'rvc_0123456789abcdef0123456789abcdef',
    token: 'server-token',
    rtcUid: 2,
    expiresAtMillis: 2_000_000,
  );

  test('microphone permission is delegated without media join', () async {
    final permission = _Permission(granted: true);
    final adapter = _Adapter();
    final service = RideVoiceCallRtcEngineService(
      permissionGateway: permission,
      engineAdapter: adapter,
    );

    expect(await service.requestMicrophonePermission(), isTrue);
    expect(permission.calls, 1);
    expect(adapter.joinCalls, 0);
  });

  test('join delegates server-derived session and media callbacks', () async {
    final adapter = _Adapter();
    final service = RideVoiceCallRtcEngineService(
      permissionGateway: _Permission(granted: true),
      engineAdapter: adapter,
    );

    var joined = 0;
    var expiring = 0;

    await service.join(
      session: session,
      onJoined: () async {
        joined += 1;
      },
      onTokenWillExpire: () async {
        expiring += 1;
      },
    );

    expect(adapter.joinCalls, 1);
    expect(adapter.session, same(session));

    await adapter.fireJoined();
    await adapter.fireTokenWillExpire();

    expect(joined, 1);
    expect(expiring, 1);
  });

  test('mute speaker renew leave and dispose are delegated', () async {
    final adapter = _Adapter();
    final service = RideVoiceCallRtcEngineService(
      permissionGateway: _Permission(granted: true),
      engineAdapter: adapter,
    );

    await service.setMuted(true);
    await service.setSpeakerphone(true);
    await service.renewToken('renewed-token');
    await service.leave();
    await service.dispose();

    expect(adapter.muted, isTrue);
    expect(adapter.speaker, isTrue);
    expect(adapter.token, 'renewed-token');
    expect(adapter.leaveCalls, 1);
    expect(adapter.disposeCalls, 1);
  });

  test('empty renewal token fails before adapter invocation', () async {
    final adapter = _Adapter();
    final service = RideVoiceCallRtcEngineService(
      permissionGateway: _Permission(granted: true),
      engineAdapter: adapter,
    );

    await expectLater(
      service.renewToken('   '),
      throwsA(
        isA<RideVoiceCallRtcMediaException>().having(
          (error) => error.code,
          'code',
          'invalid-argument',
        ),
      ),
    );
    expect(adapter.token, isNull);
  });
}

class _Permission implements RideVoiceCallRtcPermissionGateway {
  _Permission({required this.granted});

  final bool granted;
  int calls = 0;

  @override
  Future<bool> requestMicrophone() async {
    calls += 1;
    return granted;
  }
}

class _Adapter implements RideVoiceCallRtcEngineAdapter {
  int joinCalls = 0;
  int leaveCalls = 0;
  int disposeCalls = 0;
  bool? muted;
  bool? speaker;
  String? token;
  RideVoiceCallRtcSession? session;
  RideVoiceCallRtcMediaCallback? joined;
  RideVoiceCallRtcMediaCallback? expiring;

  @override
  Future<void> join({
    required RideVoiceCallRtcSession session,
    required RideVoiceCallRtcMediaCallback onJoined,
    required RideVoiceCallRtcMediaCallback onTokenWillExpire,
  }) async {
    joinCalls += 1;
    this.session = session;
    joined = onJoined;
    expiring = onTokenWillExpire;
  }

  Future<void> fireJoined() async => joined?.call();

  Future<void> fireTokenWillExpire() async => expiring?.call();

  @override
  Future<void> renewToken(String token) async {
    this.token = token;
  }

  @override
  Future<void> leave() async {
    leaveCalls += 1;
  }

  @override
  Future<void> setMuted(bool muted) async {
    this.muted = muted;
  }

  @override
  Future<void> setSpeakerphone(bool enabled) async {
    speaker = enabled;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}
