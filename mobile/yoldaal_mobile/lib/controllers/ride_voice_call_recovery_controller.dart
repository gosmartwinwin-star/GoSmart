import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/ride_voice_call_create_service.dart';
import '../services/ride_voice_call_push_hint_service.dart';
import '../services/ride_voice_call_recovery_service.dart';
import '../services/ride_voice_call_transition_service.dart';

typedef RideVoiceCallAuthenticationProbe = bool Function();
typedef RideVoiceCallEligibleRideIdProbe = String? Function();

class RideVoiceCallRecoveryController extends ChangeNotifier {
  RideVoiceCallRecoveryController({
    RideVoiceCallRecoveryService? recoveryService,
    RideVoiceCallTransitionService? transitionService,
    RideVoiceCallCreateService? createService,
    RideVoiceCallPushHintSource? hintSource,
    RideVoiceCallEligibleRideIdProbe? currentEligibleRideId,
    required RideVoiceCallAuthenticationProbe isAuthenticated,
  }) : _recoveryService = recoveryService ?? RideVoiceCallRecoveryService(),
       _transitionService =
           transitionService ?? RideVoiceCallTransitionService(),
       _createService = createService ?? RideVoiceCallCreateService(),
       _hintSource = hintSource ?? rideVoiceCallPushHintBus,
       _currentEligibleRideId = currentEligibleRideId,
       _isAuthenticated = isAuthenticated;

  final RideVoiceCallRecoveryService _recoveryService;
  final RideVoiceCallTransitionService _transitionService;
  final RideVoiceCallCreateService _createService;
  final RideVoiceCallPushHintSource _hintSource;
  final RideVoiceCallEligibleRideIdProbe? _currentEligibleRideId;
  final RideVoiceCallAuthenticationProbe _isAuthenticated;

  StreamSubscription<int>? _hintSubscription;
  RideVoiceCallRecoverySnapshot? _activeCall;
  String? _errorCode;
  String? _actionErrorCode;
  bool _actionInFlight = false;
  int _handledHintRevision = 0;
  bool _started = false;
  bool _recovering = false;
  bool _recoverAgain = false;
  bool _disposed = false;

  RideVoiceCallRecoverySnapshot? get activeCall => _activeCall;

  String? get errorCode => _errorCode;

  String? get actionErrorCode => _actionErrorCode;

  bool get actionInFlight => _actionInFlight;

  bool get canStartCall => _canStartCall();

  bool get canAccept => _isActionAllowed('accepted');

  bool get canDecline => _isActionAllowed('declined');

  bool get canCancel => _isActionAllowed('cancelled');

  bool get canConnect => _isActionAllowed('connecting');

  bool get canActivate => _isActionAllowed('active');

  bool get canEnd => _isActionAllowed('ended');

  bool get recovering => _recovering;

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

  Future<void> endCall() => _requestTransition('ended');

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
      }
    }
  }

  void _clearSignedOutState() {
    final changed =
        _activeCall != null ||
        _errorCode != null ||
        _actionErrorCode != null ||
        _actionInFlight ||
        _recoverAgain ||
        _recovering;

    _activeCall = null;
    _errorCode = null;
    _actionErrorCode = null;
    _actionInFlight = false;
    _recoverAgain = false;

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

    super.dispose();
  }
}
