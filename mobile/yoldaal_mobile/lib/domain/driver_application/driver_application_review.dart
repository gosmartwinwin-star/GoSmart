import 'dart:collection';

import 'driver_application_document_type.dart';

enum DriverApplicationReviewState {
  pendingReview,
  approved,
  awaitingDocumentResubmission,
  rejected,
  withdrawn,
}

enum DriverApplicationPublicDocumentStatus {
  pendingReview,
  approved,
  reuploadRequired,
}

enum DriverApplicationReuploadReason {
  unreadableDocument('unreadable_document', 'Belge okunamıyor.'),
  incompleteDocument('incomplete_document', 'Belge eksik.'),
  expiredDocument('expired_document', 'Belgenin geçerlilik süresi dolmuş.'),
  informationMismatch(
    'information_mismatch',
    'Belgedeki bilgiler başvuru bilgileriyle eşleşmiyor.',
  ),
  wrongDocument('wrong_document', 'Yanlış belge yüklenmiş.'),
  unsupportedDocument(
    'unsupported_document',
    'Belge formatı veya türü kabul edilmiyor.',
  );

  const DriverApplicationReuploadReason(this.wireValue, this.label);
  final String wireValue;
  final String label;
}

enum DriverApplicationFinalRejectionReason {
  personalInformationInvalid(
    'personal_information_invalid',
    'Kişisel bilgiler doğrulanamadı.',
  ),
  vehicleInformationInvalid(
    'vehicle_information_invalid',
    'Araç bilgileri doğrulanamadı.',
  ),
  documentInformationMismatch(
    'document_information_mismatch',
    'Belge bilgileri birbiriyle eşleşmiyor.',
  ),
  eligibilityRequirementsNotMet(
    'eligibility_requirements_not_met',
    'Sürücü uygunluk koşulları sağlanmıyor.',
  ),
  duplicateApplication('duplicate_application', 'Tekrarlanan başvuru.'),
  applicationInformationIncomplete(
    'application_information_incomplete',
    'Başvuru bilgileri eksik.',
  );

  const DriverApplicationFinalRejectionReason(this.wireValue, this.label);
  final String wireValue;
  final String label;
}

final class DriverApplicationReviewDocument {
  const DriverApplicationReviewDocument({
    required this.type,
    required this.status,
    this.reuploadReason,
  });

  final DriverApplicationDocumentType type;
  final DriverApplicationPublicDocumentStatus status;
  final DriverApplicationReuploadReason? reuploadReason;
  bool get requiresReupload =>
      status == DriverApplicationPublicDocumentStatus.reuploadRequired;
}

final class DriverApplicationReview {
  DriverApplicationReview({
    required this.state,
    required this.submissionVersion,
    this.finalRejectionReason,
    required List<DriverApplicationReviewDocument> documents,
  }) : documents = UnmodifiableListView(documents) {
    if (submissionVersion < 1 ||
        documents.length != DriverApplicationDocumentType.values.length ||
        documents.map((item) => item.type).toSet().length != documents.length) {
      throw const FormatException('Başvuru durumu geçersiz.');
    }
  }

  final DriverApplicationReviewState state;
  final int submissionVersion;
  final DriverApplicationFinalRejectionReason? finalRejectionReason;
  final List<DriverApplicationReviewDocument> documents;

  List<DriverApplicationReviewDocument> get requiredDocuments =>
      List.unmodifiable(documents.where((item) => item.requiresReupload));
}
