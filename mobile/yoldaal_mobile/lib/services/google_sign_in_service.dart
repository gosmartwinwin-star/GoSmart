import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../application/auth/google_sign_in_coordinator.dart';
import '../core/firebase/firebase_functions_registry.dart';

/// Returns a Firebase Auth error code only when it is safe to emit as a
/// diagnostic identifier.
///
/// The caller must pass FirebaseAuthException.code only. Arbitrary messages,
/// account data, credentials and tokens must never be passed here.
String? sanitizeFirebaseAuthCodeForGoogleLinkDiagnostic(String code) {
  if (code.isEmpty || code.length > 64) {
    return null;
  }

  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(code)) {
    return null;
  }

  return code;
}

void _debugLogUnmappedGoogleLinkFirebaseAuthCode(String code) {
  if (!kDebugMode) {
    return;
  }

  final safeCode = sanitizeFirebaseAuthCodeForGoogleLinkDiagnostic(code);

  debugPrint(
    'Google link FirebaseAuth safe error code: '
    '${safeCode ?? 'invalid-safe-code'}',
  );
}

class NativeGoogleIdentityTokenSource {
  NativeGoogleIdentityTokenSource({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _googleSignIn;

  static Future<void>? _initialization;

  Future<String> acquire() async {
    try {
      _initialization ??= _googleSignIn.initialize();

      await _initialization;

      if (!_googleSignIn.supportsAuthenticate()) {
        throw const GoogleSignInFlowException('google_auth_unavailable');
      }

      final account = await _googleSignIn.authenticate();

      final idToken = account.authentication.idToken;

      if (idToken == null || idToken.trim().isEmpty) {
        throw const GoogleSignInFlowException('invalid_google_token');
      }

      return idToken;
    } on GoogleSignInFlowException {
      rethrow;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleSignInFlowException('google_signin_cancelled');
      }

      throw const GoogleSignInFlowException('google_provider_unavailable');
    }
  }
}

bool parseGoogleLinkStateResponse(Object? data) {
  if (data is! Map) {
    throw const GoogleSignInFlowException(
      'invalid_link_state_response',
    );
  }

  if (
    data.length == 1 &&
    data.containsKey('linked') &&
    data['linked'] is bool
  ) {
    return data['linked'] as bool;
  }

  final exactConflictKeys =
      data.length == 2 &&
      data.containsKey('linked') &&
      data.containsKey('accountConflict');

  if (
    exactConflictKeys &&
    data['linked'] == false &&
    data['accountConflict'] == true
  ) {
    throw const GoogleSignInFlowException(
      'google_account_link_account_conflict',
    );
  }

  throw const GoogleSignInFlowException(
    'invalid_link_state_response',
  );
}
class CallableGoogleLinkStateResolver {
  CallableGoogleLinkStateResolver({FirebaseFunctions? functions})
    : _functions = functions;

  static const _callable = 'resolveGoogleSignInLinkState';

  final FirebaseFunctions? _functions;

  Future<bool> resolve(String idToken) async {
    try {
      final client = _functions ?? FirebaseFunctionsRegistry.client;

      final result = await client.httpsCallable(_callable).call<dynamic>(
        <String, Object?>{'idToken': idToken},
      );

      return parseGoogleLinkStateResponse(result.data);
    } on GoogleSignInFlowException {
      rethrow;
    } on FirebaseFunctionsException {
      throw const GoogleSignInFlowException('google_link_state_unavailable');
    }
  }
}

class FirebaseGoogleAuthAdapter {
  FirebaseGoogleAuthAdapter(this._auth);

  final FirebaseAuth _auth;

  OAuthCredential _credential(String idToken) =>
      GoogleAuthProvider.credential(idToken: idToken);

  Future<void> signInLinked(String idToken) async {
    try {
      final result = await _auth.signInWithCredential(_credential(idToken));

      final user = result.user;

      if (user == null) {
        throw const GoogleSignInFlowException('google_firebase_signin_failed');
      }

      await user.getIdToken(true);
    } on GoogleSignInFlowException {
      rethrow;
    } on FirebaseAuthException {
      throw const GoogleSignInFlowException('google_firebase_signin_failed');
    }
  }

  Future<void> linkCurrentUser(String idToken) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw const GoogleSignInFlowException('phone_session_missing');
    }

    try {
      await user.linkWithCredential(_credential(idToken));
    } on FirebaseAuthException catch (error) {
      late final String safeCode;

      switch (error.code) {
        case 'credential-already-in-use':
          safeCode = 'google_account_link_credential_in_use';
          break;
        case 'account-exists-with-different-credential':
        case 'email-already-in-use':
          safeCode = 'google_account_link_account_conflict';
          break;
        case 'provider-already-linked':
          safeCode = 'google_account_already_linked';
          break;
        case 'network-request-failed':
          safeCode = 'google_account_link_network_failed';
          break;
        case 'operation-not-allowed':
          safeCode = 'google_account_link_not_allowed';
          break;
        case 'invalid-credential':
          safeCode = 'google_account_link_invalid_credential';
          break;
        case 'requires-recent-login':
          safeCode = 'google_account_link_reauth_required';
          break;
        case 'user-disabled':
          safeCode = 'google_account_link_user_disabled';
          break;
        case 'internal-error':
          safeCode = 'google_account_link_internal';
          break;
        default:
          _debugLogUnmappedGoogleLinkFirebaseAuthCode(error.code);
          safeCode = 'google_account_link_failed';
      }

      throw GoogleSignInFlowException(safeCode);
    }
  }
}

GoogleSignInCoordinator buildProductionGoogleSignInCoordinator({
  required FirebaseAuth auth,
}) {
  final identity = NativeGoogleIdentityTokenSource();

  final resolver = CallableGoogleLinkStateResolver();

  final firebaseAuth = FirebaseGoogleAuthAdapter(auth);

  return GoogleSignInCoordinator(
    acquireIdToken: identity.acquire,
    resolveLinkState: resolver.resolve,
    signInLinked: firebaseAuth.signInLinked,
    linkCurrentUser: firebaseAuth.linkCurrentUser,
  );
}
