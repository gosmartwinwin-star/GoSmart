import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../application/ports.dart';
import '../core/admin_exceptions.dart';

final class FirebaseAdminCallableInvoker implements AdminCallableInvoker {
  FirebaseAdminCallableInvoker({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(
             app: Firebase.app(),
             region: 'europe-west1',
           );
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  @override
  Future<Object?> call({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AdminPanelException(
        'unauthenticated',
        reason: 'authentication_required',
      );
    }
    final token = await user.getIdTokenResult(true);
    if (token.claims?['gosmartAdmin'] is! bool ||
        token.claims?['gosmartAdmin'] != true) {
      await _auth.signOut();
      throw const AdminPanelException(
        'permission-denied',
        reason: 'admin_access_required',
      );
    }
    try {
      final result = await _functions.httpsCallable(functionName).call(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map ? details['reason'] : null;
      throw AdminPanelException(
        error.code,
        reason: reason is String ? reason : null,
      );
    } catch (_) {
      throw const AdminPanelException('unavailable');
    }
  }
}
