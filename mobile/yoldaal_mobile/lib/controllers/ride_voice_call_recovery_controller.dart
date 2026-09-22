import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/ride_voice_call_push_hint_service.dart';
import '../services/ride_voice_call_recovery_service.dart';

typedef RideVoiceCallAuthenticationProbe = bool Function();

class RideVoiceCallRecoveryController extends ChangeNotifier {
  RideVoiceCallRecoveryController({
    RideVoiceCallRecoveryService? recoveryService,
    RideVoiceCallPushHintSource? hintSource,
    required RideVoiceCallAuthenticationProbe isAuthenticated,
  }) : _recoveryService = recoveryService ?? RideVoiceCallRecoveryService(),
       _hintSource = hintSource ?? rideVoiceCallPushHintBus,
       _isAuthenticated = isAuthenticated;

  final RideVoiceCallRecoveryService _recoveryService;
  final RideVoiceCallPushHintSource _hintSource;
  final RideVoiceCallAuthenticationProbe _isAuthenticated;

  StreamSubscription<int>? _hintSubscription;
  RideVoiceCallRecoverySnapshot? _activeCall;
  String? _errorCode;
  int _handledHintRevision = 0;
  bool _started = false;
  bool _recovering = false;
  bool _recoverAgain = false;
  bool _disposed = false;

  RideVoiceCallRecoverySnapshot? get activeCall => _activeCall;

  String? get errorCode => _errorCode;

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
        _recoverAgain ||
        _recovering;

    _activeCall = null;
    _errorCode = null;
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
