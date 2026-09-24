import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ride_voice_call_rtc_session_service.dart';

typedef RideVoiceCallRtcMediaCallback = Future<void> Function();

class RideVoiceCallRtcMediaException implements Exception {
  const RideVoiceCallRtcMediaException(this.code);

  final String code;
}

abstract interface class RideVoiceCallRtcMediaGateway {
  Future<bool> requestMicrophonePermission();

  Future<void> join({
    required RideVoiceCallRtcSession session,
    required RideVoiceCallRtcMediaCallback onJoined,
    required RideVoiceCallRtcMediaCallback onTokenWillExpire,
  });

  Future<void> renewToken(String token);

  Future<void> leave();

  Future<void> setMuted(bool muted);

  Future<void> setSpeakerphone(bool enabled);

  Future<void> dispose();
}

abstract interface class RideVoiceCallRtcPermissionGateway {
  Future<bool> requestMicrophone();
}

abstract interface class RideVoiceCallRtcEngineAdapter {
  Future<void> join({
    required RideVoiceCallRtcSession session,
    required RideVoiceCallRtcMediaCallback onJoined,
    required RideVoiceCallRtcMediaCallback onTokenWillExpire,
  });

  Future<void> renewToken(String token);

  Future<void> leave();

  Future<void> setMuted(bool muted);

  Future<void> setSpeakerphone(bool enabled);

  Future<void> dispose();
}

class RideVoiceCallRtcEngineService implements RideVoiceCallRtcMediaGateway {
  RideVoiceCallRtcEngineService({
    RideVoiceCallRtcPermissionGateway? permissionGateway,
    RideVoiceCallRtcEngineAdapter? engineAdapter,
  }) : _permissionGateway =
           permissionGateway ?? _PermissionHandlerRideVoiceCallRtcGateway(),
       _engineAdapter = engineAdapter ?? _AgoraRideVoiceCallRtcEngineAdapter();

  final RideVoiceCallRtcPermissionGateway _permissionGateway;
  final RideVoiceCallRtcEngineAdapter _engineAdapter;

  @override
  Future<bool> requestMicrophonePermission() async {
    try {
      return await _permissionGateway.requestMicrophone();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> join({
    required RideVoiceCallRtcSession session,
    required RideVoiceCallRtcMediaCallback onJoined,
    required RideVoiceCallRtcMediaCallback onTokenWillExpire,
  }) async {
    try {
      await _engineAdapter.join(
        session: session,
        onJoined: onJoined,
        onTokenWillExpire: onTokenWillExpire,
      );
    } catch (_) {
      throw const RideVoiceCallRtcMediaException('unavailable');
    }
  }

  @override
  Future<void> renewToken(String token) async {
    if (token.trim().isEmpty) {
      throw const RideVoiceCallRtcMediaException('invalid-argument');
    }

    try {
      await _engineAdapter.renewToken(token);
    } catch (_) {
      throw const RideVoiceCallRtcMediaException('unavailable');
    }
  }

  @override
  Future<void> leave() async {
    try {
      await _engineAdapter.leave();
    } catch (_) {
      throw const RideVoiceCallRtcMediaException('unavailable');
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    try {
      await _engineAdapter.setMuted(muted);
    } catch (_) {
      throw const RideVoiceCallRtcMediaException('unavailable');
    }
  }

  @override
  Future<void> setSpeakerphone(bool enabled) async {
    try {
      await _engineAdapter.setSpeakerphone(enabled);
    } catch (_) {
      throw const RideVoiceCallRtcMediaException('unavailable');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _engineAdapter.dispose();
    } catch (_) {
      return;
    }
  }
}

class _PermissionHandlerRideVoiceCallRtcGateway
    implements RideVoiceCallRtcPermissionGateway {
  @override
  Future<bool> requestMicrophone() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
}

class _AgoraRideVoiceCallRtcEngineAdapter
    implements RideVoiceCallRtcEngineAdapter {
  RtcEngine? _engine;
  String? _appId;
  RtcEngineEventHandler? _handler;

  Future<RtcEngine> _ensureEngine(String appId) async {
    final existing = _engine;
    if (existing != null && _appId == appId) {
      return existing;
    }

    if (existing != null) {
      final handler = _handler;
      if (handler != null) {
        existing.unregisterEventHandler(handler);
      }
      await existing.release();
    }

    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
    await engine.enableAudio();
    await engine.disableVideo();

    _engine = engine;
    _appId = appId;
    _handler = null;
    return engine;
  }

  @override
  Future<void> join({
    required RideVoiceCallRtcSession session,
    required RideVoiceCallRtcMediaCallback onJoined,
    required RideVoiceCallRtcMediaCallback onTokenWillExpire,
  }) async {
    final engine = await _ensureEngine(session.appId);

    final previous = _handler;
    if (previous != null) {
      engine.unregisterEventHandler(previous);
    }

    final handler = RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        unawaited(onJoined());
      },
      onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
        unawaited(onTokenWillExpire());
      },
    );

    _handler = handler;
    engine.registerEventHandler(handler);

    await engine.joinChannel(
      token: session.token,
      channelId: session.channelName,
      uid: session.rtcUid,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishMicrophoneTrack: true,
        publishCameraTrack: false,
        autoSubscribeAudio: true,
        autoSubscribeVideo: false,
        enableAudioRecordingOrPlayout: true,
      ),
    );
  }

  @override
  Future<void> renewToken(String token) async {
    final engine = _engine;
    if (engine == null) {
      throw StateError('RTC engine is unavailable.');
    }
    await engine.renewToken(token);
  }

  @override
  Future<void> leave() async {
    final engine = _engine;
    if (engine == null) return;
    await engine.leaveChannel();
  }

  @override
  Future<void> setMuted(bool muted) async {
    final engine = _engine;
    if (engine == null) {
      throw StateError('RTC engine is unavailable.');
    }
    await engine.muteLocalAudioStream(muted);
  }

  @override
  Future<void> setSpeakerphone(bool enabled) async {
    final engine = _engine;
    if (engine == null) {
      throw StateError('RTC engine is unavailable.');
    }
    await engine.setEnableSpeakerphone(enabled);
  }

  @override
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _appId = null;

    if (engine == null) return;

    final handler = _handler;
    _handler = null;

    if (handler != null) {
      engine.unregisterEventHandler(handler);
    }

    try {
      await engine.leaveChannel();
    } catch (_) {
      // Release still runs so stale media resources cannot survive disposal.
    }

    await engine.release();
  }
}
