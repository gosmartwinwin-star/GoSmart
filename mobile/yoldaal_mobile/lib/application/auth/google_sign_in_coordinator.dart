enum GoogleSignInStartDisposition { signedIn, phoneVerificationRequired }

class GoogleSignInStartResult {
  const GoogleSignInStartResult._(this.disposition);

  const GoogleSignInStartResult.signedIn()
    : this._(GoogleSignInStartDisposition.signedIn);

  const GoogleSignInStartResult.phoneVerificationRequired()
    : this._(GoogleSignInStartDisposition.phoneVerificationRequired);

  final GoogleSignInStartDisposition disposition;
}

class GoogleSignInFlowException implements Exception {
  const GoogleSignInFlowException(this.code);

  final String code;
}

typedef AcquireGoogleIdToken = Future<String> Function();

typedef ResolveGoogleLinkState = Future<bool> Function(String idToken);

typedef SignInLinkedGoogleAccount = Future<void> Function(String idToken);

typedef LinkGoogleToCurrentUser = Future<void> Function(String idToken);

class GoogleSignInCoordinator {
  GoogleSignInCoordinator({
    required AcquireGoogleIdToken acquireIdToken,
    required ResolveGoogleLinkState resolveLinkState,
    required SignInLinkedGoogleAccount signInLinked,
    required LinkGoogleToCurrentUser linkCurrentUser,
  }) : _acquireIdToken = acquireIdToken,
       _resolveLinkState = resolveLinkState,
       _signInLinked = signInLinked,
       _linkCurrentUser = linkCurrentUser;

  final AcquireGoogleIdToken _acquireIdToken;
  final ResolveGoogleLinkState _resolveLinkState;
  final SignInLinkedGoogleAccount _signInLinked;
  final LinkGoogleToCurrentUser _linkCurrentUser;

  String? _pendingIdToken;

  bool get hasPendingLink => _pendingIdToken != null;

  Future<GoogleSignInStartResult> start() async {
    _pendingIdToken = null;

    final idToken = await _acquireIdToken();

    if (idToken.trim().isEmpty) {
      throw const GoogleSignInFlowException('invalid_google_token');
    }

    final linked = await _resolveLinkState(idToken);

    if (linked) {
      await _signInLinked(idToken);

      return const GoogleSignInStartResult.signedIn();
    }

    _pendingIdToken = idToken;

    return const GoogleSignInStartResult.phoneVerificationRequired();
  }

  Future<void> linkPendingAfterPhoneSignIn() async {
    final idToken = _pendingIdToken;

    if (idToken == null) {
      throw const GoogleSignInFlowException('missing_pending_google_link');
    }

    await _linkCurrentUser(idToken);

    _pendingIdToken = null;
  }

  void clearPendingLink() {
    _pendingIdToken = null;
  }
}
