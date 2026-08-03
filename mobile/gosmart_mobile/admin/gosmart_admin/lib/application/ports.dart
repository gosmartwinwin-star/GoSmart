import '../domain/admin_session.dart';
import '../domain/driver_application.dart';

abstract interface class AdminAuthGateway {
  Stream<AdminSession?> authStateChanges();
  Future<AdminSession> signIn({
    required String email,
    required String password,
  });
  Future<AdminSession?> refreshAndGetSession();
  Future<void> signOut();
}

abstract interface class AdminCallableInvoker {
  Future<Object?> call({
    required String functionName,
    required Map<String, Object?> payload,
  });
}

abstract interface class DriverApplicationAdminReadGateway {
  Future<DriverApplicationReviewPage> list({
    required DriverApplicationReviewStatus status,
    int pageSize = 20,
    DriverApplicationReviewCursor? cursor,
  });

  Future<DriverApplicationReviewDetails> getDetails({
    required String applicationId,
  });
}
