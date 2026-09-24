import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/ride_voice_call_create_service.dart';
import '../services/ride_voice_call_push_hint_service.dart';
import '../services/ride_voice_call_recovery_service.dart';
import '../services/ride_voice_call_rtc_engine_service.dart';
import '../services/ride_voice_call_rtc_session_service.dart';
import '../services/ride_voice_call_transition_service.dart';

typedef RideVoiceCallAuthenticationProbe = bool Function();
typedef RideVoiceCallEligibleRideIdProbe = String? Function();

class RideVoiceCallRecoveryController extends ChangeNotifier {
  RideVoiceCallRecoveryController({
    RideVoiceCallRecoveryService? recoveryService,
    RideVoiceCallTransitionService? transitionService,
    RideVoiceCallCreateService? createService,
    RideVoiceCallRtcSessionGateway? rtcSessionService,
    RideVoiceCallRtcMediaGateway? rtcMediaGateway,
    RideVoiceCallPushHintSource? hintSource,
    RideVoiceCallEligibleRideIdProbe? currentEligibleRideId,
    required RideVoiceCallAuthenticationProbe isAuthenticated,
  }) : _recoveryService = recoveryService ?? RideVoiceCallRecoveryService(),
       _transitionService =
           transitionService ?? RideVoiceCallTransitionService(),
       _createService = createService ?? RideVoiceCallCreateService(),
       _rtcSessionService =
           rtcSessionService ?? RideVoiceCallRtcSessionService(),
       _rtcMediaGateway = rtcMediaGateway ?? RideVoiceCallRtcEngineService(),
       _hintSource = hintSource ?? rideVoiceCallPushHintBus,
       _currentEligibleRideId = currentEligibleRideId,
       _isAuthenticated = isAuthenticated;

  final RideVoiceCallRecoveryService _recoveryService;
  final RideVoiceCallTransitionService _transitionService;
  final RideVoiceCallCreateService _createService;
  final RideVoiceCallRtcSessionGateway _rtcSessionService;
  final RideVoiceCallRtcMediaGateway _rtcMediaGateway;
  final RideVoiceCallPushHintSource _hintSource;
  final RideVoiceCallEligibleRideIdProbe? _currentEligibleRideId;
  final RideVoiceCallAuthenticationProbe _isAuthenticated;

  StreamSubscription<int>? _hintSubscription;
  RideVoiceCallRecoverySnapshot? _activeCall;
  RideVoiceCallRtcSession? _rtcSession;
  String? _rtcCallId;
  String? _errorCode;
  String? _actionErrorCode;
  String? _rtcErrorCode;
  bool _actionInFlight = false;
  bool _rtcSyncInFlight = false;
  bool _rtcTokenRefreshInFlight = false;
  bool _rtcJoining = false;
  bool _rtcConnected = false;
  bool _rtcMuted = false;
  bool _rtcSpeakerphoneEnabled = false;
  int _handledHintRevision = 0;
  bool _started = false;
  bool _recovering = false;
  bool _recoverAgain = false;
  bool _disposed = false;

  RideVoiceCallRecoverySnapshot? get activeCall => _activeCall;

  String? get errorCode => _errorCode;

  String? get actionErrorCode => _actionErrorCode;

  String? get rtcErrorCode => _rtcErrorCode;

  bool get actionInFlight => _actionInFlight;

  bool get canStartCall => _canStartCall();

  bool get canAccept => _isActionAllowed('accepted');

  bool get canDecline => _isActionAllowed('declined');

  bool get canCancel => _isActionAllowed('cancelled');

  bool get canConnect => _isActionAllowed('connecting');

  bool get canActivate => _isActionAllowed('active');

  bool get canEnd => _isActionAllowed('ended');

  bool get recovering => _recovering;

  bool get rtcJoining => _rtcJoining;

  bool get rtcConnected => _rtcConnected;

  bool get rtcMuted => _rtcMuted;

  bool get rtcSpeakerphoneEnabled => _rtcSpeakerphoneEnabled;

  bool get canControlRtc => _rtcConnected && !_disposed;

  int get handledHintRevision => _handledHintRevision;

  void start() {
    if (_started || _disposed) return;

    _started = true;
    _handledHintRevision = _hintSource.revision;
    _hintSubscription = _hintSource.revisions.listen(_handleHintRevision);

    final latestRevision = _hintSource.revision;
    if (latestRevision > _handledHintRevision) {
      _handledHintRevision = latestRevision;
    }

    unawaited(_requestRecovery());
  }

  void authChanged() {
    if (_disposed) return;

    if (!_authenticated()) {
      _clearSignedOutState();
      return;
    }

    unawaited(_requestRecovery());
  }

  void appResumed() {
    if (_disposed) return;
    unawaited(_requestRecovery());
  }

  Future<void> recoverNow() => _requestRecovery();

  Future<void> startCall() async {
    if (_disposed || _actionInFlight) return;

    if (!_authenticated()) {
      _clearSignedOutState();
      return;
    }

    if (_activeCall != null) {
      _actionErrorCode = 'failed-precondition';
      notifyListeners();
      return;
    }

    final rideId = _eligibleRideId();
    if (rideId == null) {
      _actionErrorCode = 'failed-precondition';
      notifyListeners();
      return;
    }

    _actionInFlight = true;
    _actionErrorCode = null;
    notifyListeners();

    try {
      await _createService.create(rideId: rideId);

      if (_disposed) return;
      await _requestRecovery();
    } on RideVoiceCallCreateException catch (error) {
      if (_disposed) return;
      _actionErrorCode = error.code;
    } finally {
      if (!_disposed) {
        _actionInFlight = false;
        notifyListeners();
      }
    }
  }

  bool _canStartCall() {
    if (_disposed || _actionInFlight || _activeCall != null) {
      return false;
    }
    if (!_authenticated()) {
      return false;
    }
    return _eligibleRideId() != null;
  }

  String? _eligibleRideId() {
    final probe = _currentEligibleRideId;
    if (probe == null) return null;

    try {
      final value = probe();
      if (value == null) return null;
      final normalized = value.trim();
      return normalized.isEmpty ? null : normalized;
    } catch (_) {
      return null;
    }
  }

  Future<void> acceptCall() => _requestTransition('accepted');

  Future<void> declineCall() => _requestTransition('declined');

  Future<void> cancelCall() => _requestTransition('cancelled');

  Future<void> connectCall() => _requestTransition('connecting');

  Future<void> activateCall() => _requestTransition('active');

  Future<void> endCall() async {
    await _requestTransition('ended');
    await _leaveRtcMedia();
  }

  Future<void> toggleMuted() async {
    if (_disposed || !canControlRtc) return;

    final next = !_rtcMuted;
    try {
      await _rtcMediaGateway.setMuted(next);
      if (_disposed) return;
      _rtcMuted = next;
      _rtcErrorCode = null;
      notifyListeners();
    } on RideVoiceCallRtcMediaException catch (error) {
      if (_disposed) return;
      _rtcErrorCode = error.code;
      notifyListeners();
    }
  }

  Future<void> toggleSpeakerphone() async {
    if (_disposed || !canControlRtc) return;

    final next = !_rtcSpeakerphoneEnabled;
    try {
      await _rtcMediaGateway.setSpeakerphone(next);
      if (_disposed) return;
      _rtcSpeakerphoneEnabled = next;
      _rtcErrorCode = null;
      notifyListeners();
    } on RideVoiceCallRtcMediaException catch (error) {
      if (_disposed) return;
      _rtcErrorCode = error.code;
      notifyListeners();
    }
  }

  bool _isActionAllowed(String targetState) {
    final call = _activeCall;
    if (call == null) return false;
    return _isActionAllowedFor(call, targetState);
  }

  bool _isActionAllowedFor(
    RideVoiceCallRecoverySnapshot call,
    String targetState,
  ) {
    final participantRole =
        call.role == RideVoiceCallRecoveryRole.driver ||
        call.role == RideVoiceCallRecoveryRole.passenger;
    if (!participantRole) return false;

    if (targetState == 'accepted' || targetState == 'declined') {
      return call.state == RideVoiceCallRecoveryState.ringing &&
          call.side == RideVoiceCallRecoverySide.callee;
    }

    if (targetState == 'cancelled') {
      return call.state == RideVoiceCallRecoveryState.ringing &&
          call.side == RideVoiceCallRecoverySide.caller;
    }

    if (targetState == 'connecting') {
      return call.state == RideVoiceCallRecoveryState.accepted;
    }

    if (targetState == 'active') {
      return call.state == RideVoiceCallRecoveryState.connecting;
    }

    if (targetState == 'ended') {
      return call.state == RideVoiceCallRecoveryState.accepted ||
          call.state == RideVoiceCallRecoveryState.connecting ||
          call.state == RideVoiceCallRecoveryState.active;
    }

    return false;
  }

  Future<void> _requestTransition(String targetState) async {
    if (_disposed || _actionInFlight) return;

    if (!_authenticated()) {
      _clearSignedOutState();
      return;
    }

    final call = _activeCall;
    if (call == null || !_isActionAllowedFor(call, targetState)) {
      _actionErrorCode = 'failed-precondition';
      notifyListeners();
      return;
    }

    _actionInFlight = true;
    _actionErrorCode = null;
    notifyListeners();

    try {
      await _transitionService.transition(
        rideId: call.rideId,
        callId: call.callId,
        targetState: targetState,
      );

      if (_disposed) return;
      await _requestRecovery();
    } on RideVoiceCallTransitionException catch (error) {
      if (_disposed) return;
      _actionErrorCode = error.code;
    } finally {
      if (!_disposed) {
        _actionInFlight = false;
        notifyListeners();
      }
    }
  }

  void _handleHintRevision(int revision) {
    if (_disposed || revision <= _handledHintRevision) return;

    _handledHintRevision = revision;
    unawaited(_requestRecovery());
  }

  bool _authenticated() {
    try {
      return _isAuthenticated();
    } catch (_) {
      return false;
    }
  }

  Future<void> _requestRecovery() async {
    if (_disposed) return;

    if (!_authenticated()) {
      _clearSignedOutState();
      return;
    }

    if (_recovering) {
      _recoverAgain = true;
      return;
    }

    _recovering = true;
    notifyListeners();

    try {
      do {
        _recoverAgain = false;

        try {
          final recovered = await _recoveryService.recover();

          if (_disposed) return;

          _activeCall = recovered;
          _errorCode = null;
        } on RideVoiceCallRecoveryException catch (error) {
          if (_disposed) return;

          _errorCode = error.code;
        }

        if (!_disposed) {
          notifyListeners();
        }
      } while (_recoverAgain && !_disposed && _authenticated());
    } finally {
      if (!_disposed) {
        _recovering = false;
        notifyListeners();
        unawaited(_synchronizeRtcMedia());
      }
    }
  }

  Future<void> _synchronizeRtcMedia() async {
    if (_disposed || _rtcSyncInFlight) return;

    final call = _activeCall;
    if (!_authenticated() ||
        call == null ||
        call.state == RideVoiceCallRecoveryState.ringing) {
      await _leaveRtcMedia();
      return;
    }

    if (_rtcCallId == call.callId && (_rtcJoining || _rtcConnected)) {
      return;
    }

    _rtcSyncInFlight = true;

    try {
      if (_rtcCallId != null && _rtcCallId != call.callId) {
        await _leaveRtcMedia();
      }

      final granted = await _rtcMediaGateway.requestMicrophonePermission();
      if (_disposed) return;

      if (!granted) {
        _rtcErrorCode = 'permission-denied';
        notifyListeners();
        return;
      }

      final session = await _rtcSessionService.getActiveSession();
      if (_disposed) return;

      final current = _activeCall;
      if (current == null ||
          current.callId != call.callId ||
          current.state == RideVoiceCallRecoveryState.ringing) {
        return;
      }

      _rtcSession = session;
      _rtcErrorCode = null;

      if (current.state == RideVoiceCallRecoveryState.accepted) {
        await _requestTransition('connecting');
        if (_disposed) return;
      }

      final ready = _activeCall;
      if (ready == null ||
          ready.callId != call.callId ||
          (ready.state != RideVoiceCallRecoveryState.connecting &&
              ready.state != RideVoiceCallRecoveryState.active)) {
        return;
      }

      if (_rtcCallId == ready.callId && (_rtcJoining || _rtcConnected)) {
        return;
      }

      _rtcCallId = ready.callId;
      _rtcJoining = true;
      _rtcConnected = false;
      _rtcMuted = false;
      _rtcSpeakerphoneEnabled = false;
      notifyListeners();

      await _rtcMediaGateway.join(
        session: session,
        onJoined: () => _handleRtcJoined(ready.callId),
        onTokenWillExpire: () => _handleRtcTokenWillExpire(ready.callId),
      );
    } on RideVoiceCallRtcSessionException catch (error) {
      if (_disposed) return;
      _rtcJoining = false;
      _rtcErrorCode = error.code;
      notifyListeners();
    } on RideVoiceCallRtcMediaException catch (error) {
      if (_disposed) return;
      _rtcJoining = false;
      _rtcErrorCode = error.code;
      notifyListeners();
    } finally {
      _rtcSyncInFlight = false;
    }
  }

  Future<void> _handleRtcJoined(String callId) async {
    if (_disposed || _rtcCallId != callId) return;

    _rtcJoining = false;
    _rtcConnected = true;
    _rtcErrorCode = null;
    notifyListeners();

    final call = _activeCall;
    if (call != null &&
        call.callId == callId &&
        call.state == RideVoiceCallRecoveryState.connecting) {
      await activateCall();
    }
  }

  Future<void> _handleRtcTokenWillExpire(String callId) async {
    if (_disposed ||
        _rtcCallId != callId ||
        !_rtcConnected ||
        _rtcTokenRefreshInFlight) {
      return;
    }

    _rtcTokenRefreshInFlight = true;

    try {
      final previous = _rtcSession;
      if (previous == null) return;

      final refreshed = await _rtcSessionService.getActiveSession();
      if (_disposed || _rtcCallId != callId) return;

      if (refreshed.channelName != previous.channelName ||
          refreshed.rtcUid != previous.rtcUid ||
          refreshed.appId != previous.appId) {
        _rtcErrorCode = 'invalid-response';
        notifyListeners();
        return;
      }

      await _rtcMediaGateway.renewToken(refreshed.token);
      if (_disposed || _rtcCallId != callId) return;

      _rtcSession = refreshed;
      _rtcErrorCode = null;
      notifyListeners();
    } on RideVoiceCallRtcSessionException catch (error) {
      if (_disposed) return;
      _rtcErrorCode = error.code;
      notifyListeners();
    } on RideVoiceCallRtcMediaException catch (error) {
      if (_disposed) return;
      _rtcErrorCode = error.code;
      notifyListeners();
    } finally {
      _rtcTokenRefreshInFlight = false;
    }
  }

  Future<void> _leaveRtcMedia() async {
    if (_disposed) return;

    final hadRtcState =
        _rtcCallId != null ||
        _rtcJoining ||
        _rtcConnected ||
        _rtcSession != null ||
        _rtcMuted ||
        _rtcSpeakerphoneEnabled;

    _rtcCallId = null;
    _rtcSession = null;
    _rtcJoining = false;
    _rtcConnected = false;
    _rtcMuted = false;
    _rtcSpeakerphoneEnabled = false;

    if (!hadRtcState) {
      return;
    }

    try {
      await _rtcMediaGateway.leave();
    } on RideVoiceCallRtcMediaException catch (error) {
      if (_disposed) return;
      _rtcErrorCode = error.code;
    }

    if (!_disposed) {
      notifyListeners();
    }
  }

  void _clearSignedOutState() {
    final changed =
        _activeCall != null ||
        _errorCode != null ||
        _actionErrorCode != null ||
        _rtcErrorCode != null ||
        _actionInFlight ||
        _recoverAgain ||
        _recovering ||
        _rtcCallId != null ||
        _rtcJoining ||
        _rtcConnected;

    _activeCall = null;
    _errorCode = null;
    _actionErrorCode = null;
    _rtcErrorCode = null;
    _actionInFlight = false;
    _recoverAgain = false;

    unawaited(_leaveRtcMedia());

    if (changed && !_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;

    _disposed = true;
    final subscription = _hintSubscription;
    _hintSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    unawaited(_rtcMediaGateway.dispose());
    super.dispose();
  }
}
