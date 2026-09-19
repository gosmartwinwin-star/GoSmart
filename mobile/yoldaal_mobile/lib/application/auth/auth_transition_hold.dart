import 'package:flutter/foundation.dart';

enum AuthRootGateDecision { loading, login, authenticated }

AuthRootGateDecision resolveAuthRootGateDecision({
  required bool connectionWaiting,
  required bool transitionHeld,
  required bool hasError,
  required bool hasUser,
}) {
  if (connectionWaiting || transitionHeld) {
    return AuthRootGateDecision.loading;
  }

  if (hasError || !hasUser) {
    return AuthRootGateDecision.login;
  }

  return AuthRootGateDecision.authenticated;
}

class AuthTransitionHold extends ChangeNotifier {
  bool _isHeld = false;

  bool get isHeld => _isHeld;

  void begin() {
    // Intentionally do not notify here.
    //
    // Google-first linking begins while the root auth state is signed out.
    // Avoid rebuilding/discarding the active LoginScreen before the phone
    // credential is entered. The Firebase auth event itself will rebuild the
    // root stream, which will then observe isHeld == true.
    _isHeld = true;
  }

  void release() {
    if (!_isHeld) {
      return;
    }

    _isHeld = false;
    notifyListeners();
  }
}

final AuthTransitionHold authTransitionHold = AuthTransitionHold();
