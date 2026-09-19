import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../application/auth/google_sign_in_coordinator.dart';
import '../core/firebase/firebase_functions_registry.dart';

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

      final data = result.data;

      if (data is! Map) {
        throw const GoogleSignInFlowException('invalid_link_state_response');
      }

      if (data.length != 1 ||
          !data.containsKey('linked') ||
          data['linked'] is! bool) {
        throw const GoogleSignInFlowException('invalid_link_state_response');
      }

      return data['linked'] as bool;
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

      await user.getIdToken(true);
    } on FirebaseAuthException {
      throw const GoogleSignInFlowException('google_account_link_failed');
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
