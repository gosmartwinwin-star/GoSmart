import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../application/ports.dart';
import '../core/admin_exceptions.dart';
import '../domain/admin_session.dart';

final class FirebaseAdminAuthGateway implements AdminAuthGateway {
  FirebaseAdminAuthGateway({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;
  bool _persistenceConfigured = false;

  Future<void> _configurePersistence() async {
    if (kIsWeb && !_persistenceConfigured) {
      await _auth.setPersistence(Persistence.SESSION);
      _persistenceConfigured = true;
    }
  }

  @override
  Stream<AdminSession?> authStateChanges() =>
      _auth.authStateChanges().asyncMap((user) async {
        if (user == null) return null;
        return _sessionFor(user);
      });

  @override
  Future<AdminSession> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _configurePersistence();
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AdminAuthenticationException('authentication_unavailable');
      }
      final session = await _sessionFor(user);
      if (!session.hasGoSmartAdminClaim) {
        await _auth.signOut();
        throw const AdminAuthenticationException('admin_access_required');
      }
      return session;
    } on AdminAuthenticationException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      if (const {
        'invalid-credential',
        'wrong-password',
        'user-not-found',
        'invalid-email',
      }.contains(error.code)) {
        throw const AdminAuthenticationException('invalid_credentials');
      }
      throw const AdminAuthenticationException('authentication_unavailable');
    } catch (_) {
      throw const AdminAuthenticationException('unknown_authentication_error');
    }
  }

  @override
  Future<AdminSession?> refreshAndGetSession() async {
    try {
      await _configurePersistence();
      final user = _auth.currentUser;
      if (user == null) return null;
      final session = await _sessionFor(user);
      if (!session.hasGoSmartAdminClaim) {
        await _auth.signOut();
        throw const AdminAuthenticationException('admin_access_required');
      }
      return session;
    } on AdminAuthenticationException {
      rethrow;
    } catch (_) {
      throw const AdminAuthenticationException('session_expired');
    }
  }

  Future<AdminSession> _sessionFor(User user) async {
    final token = await user.getIdTokenResult(true);
    final hasClaim =
        token.claims?['gosmartAdmin'] is bool &&
        token.claims?['gosmartAdmin'] == true;
    return AdminSession(
      userId: user.uid,
      email: user.email,
      hasGoSmartAdminClaim: hasClaim,
    );
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
