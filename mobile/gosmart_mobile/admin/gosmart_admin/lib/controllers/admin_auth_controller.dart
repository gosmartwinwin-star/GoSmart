import 'dart:async';
import 'package:flutter/foundation.dart';
import '../application/ports.dart';
import '../core/admin_exceptions.dart';
import '../domain/admin_session.dart';

final class AdminAuthController extends ChangeNotifier {
  AdminAuthController(this._gateway);
  final AdminAuthGateway _gateway;
  StreamSubscription<AdminSession?>? _subscription;
  bool isInitializing = true;
  bool isSigningIn = false;
  AdminSession? session;
  String? errorMessage;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_disposed) return;
    try {
      session = await _gateway.refreshAndGetSession();
      if (session != null && session!.hasGoSmartAdminClaim != true) {
        await _gateway.signOut();
        session = null;
      }
      _subscription = _gateway.authStateChanges().listen((value) async {
        if (value == null) {
          session = null;
          _notify();
        } else {
          await refreshSession();
        }
      });
    } catch (error) {
      session = null;
      errorMessage = adminAuthMessage(error);
    } finally {
      isInitializing = false;
      _notify();
    }
  }

  Future<bool> signIn(String email, String password) async {
    if (_disposed || isSigningIn) return false;
    isSigningIn = true;
    errorMessage = null;
    _notify();
    try {
      final next = await _gateway.signIn(email: email, password: password);
      if (next.hasGoSmartAdminClaim != true) {
        await _gateway.signOut();
        throw const AdminAuthenticationException('admin_access_required');
      }
      session = next;
      return true;
    } catch (error) {
      session = null;
      errorMessage = adminAuthMessage(error);
      return false;
    } finally {
      isSigningIn = false;
      _notify();
    }
  }

  Future<void> refreshSession() async {
    try {
      final next = await _gateway.refreshAndGetSession();
      if (next == null || next.hasGoSmartAdminClaim != true) {
        await _gateway.signOut();
        session = null;
      } else {
        session = next;
      }
    } catch (_) {
      await _gateway.signOut();
      session = null;
    }
    _notify();
  }

  Future<void> signOut() async {
    await _gateway.signOut();
    session = null;
    errorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
