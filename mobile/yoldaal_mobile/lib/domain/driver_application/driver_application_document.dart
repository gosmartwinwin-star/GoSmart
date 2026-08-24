import 'driver_application_document_status.dart';
import 'driver_application_document_type.dart';

class DriverApplicationDocument {
  final DriverApplicationDocumentType type;
  final DriverApplicationDocumentStatus status;
  final String? storagePath;
  final String? contentType;
  final int? sizeBytes;
  final DateTime? uploadedAt;
  final DateTime? reviewedAt;
  final String? rejectionReasonCode;
  final String? documentSetId;
  final int? submissionVersion;

  DriverApplicationDocument({
    required this.type,
    required this.status,
    this.storagePath,
    this.contentType,
    this.sizeBytes,
    this.uploadedAt,
    this.reviewedAt,
    this.rejectionReasonCode,
    this.documentSetId,
    this.submissionVersion,
  }) {
    if (storagePath != null && storagePath!.trim().isEmpty) {
      throw ArgumentError.value(storagePath, 'storagePath');
    }
    if (contentType != null &&
        !type.allowedContentTypes.contains(contentType)) {
      throw ArgumentError.value(contentType, 'contentType');
    }
    if (sizeBytes != null && sizeBytes! <= 0) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes');
    }
    if (submissionVersion != null && submissionVersion! <= 0) {
      throw ArgumentError.value(submissionVersion, 'submissionVersion');
    }
    final requiresUpload = status != DriverApplicationDocumentStatus.missing;
    if (requiresUpload &&
        (storagePath == null ||
            contentType == null ||
            sizeBytes == null ||
            uploadedAt == null)) {
      throw ArgumentError(
        'Yüklenmiş belge metadata alanları eksiksiz olmalıdır.',
      );
    }
    final requiresSubmission = switch (status) {
      DriverApplicationDocumentStatus.pendingReview ||
      DriverApplicationDocumentStatus.approved ||
      DriverApplicationDocumentStatus.reuploadRequired => true,
      _ => false,
    };
    if (requiresSubmission &&
        ((documentSetId?.trim().isEmpty ?? true) ||
            submissionVersion == null)) {
      throw ArgumentError('İnceleme belgesinde başvuru kimliği zorunludur.');
    }
    if (reviewedAt != null &&
        uploadedAt != null &&
        reviewedAt!.isBefore(uploadedAt!)) {
      throw ArgumentError.value(reviewedAt, 'reviewedAt');
    }
  }
}
