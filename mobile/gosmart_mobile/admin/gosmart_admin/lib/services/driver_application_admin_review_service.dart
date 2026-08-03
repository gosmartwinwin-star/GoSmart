import '../application/ports.dart';
import '../domain/driver_application.dart';

final class DriverApplicationAdminReviewService
    implements DriverApplicationAdminReviewGateway {
  DriverApplicationAdminReviewService(this._invoker, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final AdminCallableInvoker _invoker;
  final DateTime Function() _now;

  Map<String, Object?> _context(
    String applicationId,
    DriverApplicationReviewContext context,
  ) {
    if (applicationId.trim().isEmpty || context.documentSetId.isEmpty) {
      throw const FormatException('Invalid review request');
    }
    return <String, Object?>{
      'applicationId': applicationId.trim(),
      'submissionVersion': context.submissionVersion,
      'documentSetId': context.documentSetId,
    };
  }

  @override
  Future<DriverApplicationDocumentPreview> createDocumentPreview({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
  }) async {
    final response = await _invoker.call(
      functionName: 'createDriverApplicationDocumentReviewUrl',
      payload: <String, Object?>{
        ..._context(applicationId, reviewContext),
        'documentType': documentType.name,
      },
    );
    final map = _map(response);
    final url = map['url'];
    final expiry = map['expiresAtMillis'];
    final contentType = map['contentType'];
    final size = map['sizeBytes'];
    if (url is! String ||
        url.trim().isEmpty ||
        expiry is! int ||
        expiry < 0 ||
        contentType is! String ||
        size is! int ||
        size < 1) {
      throw const FormatException('Invalid preview response');
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true);
    final preview = DriverApplicationDocumentPreview(
      rendererUri: Uri.parse(url),
      contentType: contentType,
      expiresAt: expiresAt,
      documentType: documentType,
      sizeBytes: size,
    );
    if (!preview.isReusableAt(_now())) {
      throw const FormatException('Expired preview response');
    }
    return preview;
  }

  @override
  Future<void> approveDocument({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
  }) => _documentMutation(
    applicationId: applicationId,
    reviewContext: reviewContext,
    documentType: documentType,
    decision: 'approve',
    reasonCode: null,
  );

  @override
  Future<void> requestDocumentReupload({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
    required DriverDocumentReuploadReason reason,
  }) => _documentMutation(
    applicationId: applicationId,
    reviewContext: reviewContext,
    documentType: documentType,
    decision: 'requireReupload',
    reasonCode: reason.wireValue,
  );

  Future<void> _documentMutation({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
    required String decision,
    required String? reasonCode,
  }) async {
    final response = await _invoker.call(
      functionName: 'reviewDriverApplicationDocument',
      payload: <String, Object?>{
        ..._context(applicationId, reviewContext),
        'documentType': documentType.name,
        'decision': decision,
        // ignore: use_null_aware_elements
        if (reasonCode != null) 'reasonCode': reasonCode,
      },
    );
    final map = _map(response);
    if (map['applicationStatus'] is! String ||
        map['documentStatus'] is! String ||
        map['reviewedAtMillis'] is! int) {
      throw const FormatException('Invalid document review response');
    }
  }

  @override
  Future<void> approveApplication({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
  }) => _applicationMutation(
    applicationId: applicationId,
    reviewContext: reviewContext,
    decision: 'approve',
    rejectionReasonCode: null,
  );

  @override
  Future<void> rejectApplication({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverApplicationRejectionReason reason,
  }) => _applicationMutation(
    applicationId: applicationId,
    reviewContext: reviewContext,
    decision: 'reject',
    rejectionReasonCode: reason.wireValue,
  );

  Future<void> _applicationMutation({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required String decision,
    required String? rejectionReasonCode,
  }) async {
    final response = await _invoker.call(
      functionName: 'reviewDriverApplication',
      payload: <String, Object?>{
        ..._context(applicationId, reviewContext),
        'decision': decision,
        // ignore: use_null_aware_elements
        if (rejectionReasonCode != null)
          'rejectionReasonCode': rejectionReasonCode,
      },
    );
    final map = _map(response);
    if (map['status'] is! String ||
        map['reviewedAtMillis'] is! int ||
        map['driverProfileCreated'] is! bool) {
      throw const FormatException('Invalid application review response');
    }
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('Invalid review response');
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
