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

abstract interface class DriverApplicationAdminReviewGateway {
  Future<DriverApplicationDocumentPreview> createDocumentPreview({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
  });
  Future<void> approveDocument({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
  });
  Future<void> requestDocumentReupload({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
    required DriverDocumentReuploadReason reason,
  });
  Future<void> approveApplication({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
  });
  Future<void> rejectApplication({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverApplicationRejectionReason reason,
  });
}
