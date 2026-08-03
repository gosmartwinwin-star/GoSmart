import 'dart:collection';

enum DriverApplicationReviewStatus {
  pendingReview('İnceleme Bekleyen'),
  approved('Onaylanan'),
  rejected('Onaylanmayan'),
  withdrawn('Geri Çekilen');

  const DriverApplicationReviewStatus(this.label);
  final String label;
}

enum DriverWorkType {
  vehicleOwner('Araç Sahibi'),
  employedDriver('Çalışan Sürücü'),
  shiftDriver('Vardiyalı Sürücü');

  const DriverWorkType(this.label);
  final String label;
}

enum RegistrationOwnerType {
  applicant('Başvuru Sahibi'),
  otherIndividual('Başka Kişi'),
  company('Şirket');

  const RegistrationOwnerType(this.label);
  final String label;
}

enum DriverDocumentType {
  driverLicenseFront('Ehliyet Ön'),
  driverLicenseBack('Ehliyet Arka'),
  identityCardFront('Kimlik Ön'),
  identityCardBack('Kimlik Arka'),
  vehicleRegistration('Araç Ruhsatı'),
  driverProfilePhoto('Sürücü Fotoğrafı'),
  criminalRecord('Adli Sicil Kaydı');

  const DriverDocumentType(this.label);
  final String label;
}

enum DocumentReviewStatus {
  pendingReview('İnceleme Bekliyor'),
  approved('Onaylandı'),
  reuploadRequired('Yeniden Yükleme Gerekli');

  const DocumentReviewStatus(this.label);
  final String label;
}

enum DriverDocumentReuploadReason {
  unreadableDocument('unreadable_document', 'Belge okunamıyor.'),
  incompleteDocument('incomplete_document', 'Belge eksik görünüyor.'),
  expiredDocument('expired_document', 'Belgenin geçerlilik süresi dolmuş.'),
  informationMismatch('information_mismatch', 'Belgedeki bilgiler eşleşmiyor.'),
  wrongDocument('wrong_document', 'Farklı bir belge yüklenmiş.'),
  unsupportedDocument('unsupported_document', 'Belge biçimi desteklenmiyor.');

  const DriverDocumentReuploadReason(this.wireValue, this.label);
  final String wireValue;
  final String label;
}

enum DriverApplicationRejectionReason {
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
    'Uygunluk koşulları sağlanmıyor.',
  ),
  duplicateApplication('duplicate_application', 'Tekrarlanan başvuru.'),
  applicationInformationIncomplete(
    'application_information_incomplete',
    'Başvuru bilgileri eksik.',
  );

  const DriverApplicationRejectionReason(this.wireValue, this.label);
  final String wireValue;
  final String label;
}

final class DriverApplicationDocumentPreview {
  DriverApplicationDocumentPreview({
    required Uri rendererUri,
    required this.contentType,
    required this.expiresAt,
    required this.documentType,
    required this.sizeBytes,
  }) : _rendererUri = rendererUri {
    if (rendererUri.scheme != 'https' ||
        rendererUri.host.isEmpty ||
        rendererUri.hasFragment ||
        !expiresAt.isUtc ||
        sizeBytes < 1 ||
        !const {
          'image/jpeg',
          'image/png',
          'application/pdf',
        }.contains(contentType)) {
      throw const FormatException('Invalid document preview');
    }
  }
  final Uri _rendererUri;
  final String contentType;
  final DateTime expiresAt;
  final DriverDocumentType documentType;
  final int sizeBytes;
  Uri get rendererUri => _rendererUri;
  bool isReusableAt(DateTime now) =>
      expiresAt.isAfter(now.toUtc().add(const Duration(seconds: 15)));
  @override
  String toString() =>
      'DriverApplicationDocumentPreview('
      'documentType: ${documentType.name}, contentType: $contentType, '
      'expiresAt: $expiresAt, url: [REDACTED])';
}

final class DriverApplicationReviewSummary {
  const DriverApplicationReviewSummary({
    required this.applicationId,
    required this.status,
    required this.submittedAt,
    required this.updatedAt,
    required this.submissionVersion,
    required this.workType,
    required this.vehicleBrand,
    required this.vehicleModel,
    required this.vehicleModelYear,
    required this.registrationOwnerType,
  });
  final String applicationId;
  final DriverApplicationReviewStatus status;
  final DateTime submittedAt;
  final DateTime updatedAt;
  final int submissionVersion;
  final DriverWorkType workType;
  final String vehicleBrand;
  final String vehicleModel;
  final int vehicleModelYear;
  final RegistrationOwnerType registrationOwnerType;
}

final class DriverApplicationReviewCursor {
  const DriverApplicationReviewCursor({
    required this.submittedAt,
    required this.applicationId,
  });
  final DateTime submittedAt;
  final String applicationId;
}

final class DriverApplicationReviewPage {
  DriverApplicationReviewPage({
    required List<DriverApplicationReviewSummary> items,
    required this.nextCursor,
  }) : items = UnmodifiableListView(items);
  final List<DriverApplicationReviewSummary> items;
  final DriverApplicationReviewCursor? nextCursor;
}

final class DriverApplicationReviewContext {
  DriverApplicationReviewContext({
    required this.submissionVersion,
    required String documentSetId,
  }) : documentSetId = documentSetId.trim() {
    if (submissionVersion < 1 || this.documentSetId.isEmpty) {
      throw const FormatException('Invalid review context');
    }
  }
  final int submissionVersion;
  final String documentSetId;
  @override
  String toString() => 'DriverApplicationReviewContext(redacted)';
}

final class DriverApplicationReviewApplication {
  const DriverApplicationReviewApplication({
    required this.applicationId,
    required this.status,
    required this.submittedAt,
    required this.updatedAt,
    this.reviewedAt,
    required this.submissionVersion,
    required this.fullName,
    required this.verifiedPhoneNumber,
    this.email,
    this.driverTaxiStandName,
    this.driverTaxiStandAddress,
    required this.workType,
    required this.vehiclePlate,
    required this.vehicleBrand,
    required this.vehicleModel,
    required this.vehicleModelYear,
    required this.registrationOwnerType,
    required this.hasVehicleUseAuthorization,
    this.vehicleTaxiStandName,
    required this.informationAccuracyAccepted,
    required this.documentValidityNotificationAccepted,
    required this.documentProcessingNoticeAccepted,
    required this.kvkkNoticeAccepted,
    required this.termsAccepted,
    required this.marketingConsent,
    this.rejectionReasonCode,
  });
  final String applicationId;
  final DriverApplicationReviewStatus status;
  final DateTime submittedAt;
  final DateTime updatedAt;
  final DateTime? reviewedAt;
  final int submissionVersion;
  final String fullName;
  final String verifiedPhoneNumber;
  final String? email;
  final String? driverTaxiStandName;
  final String? driverTaxiStandAddress;
  final DriverWorkType workType;
  final String vehiclePlate;
  final String vehicleBrand;
  final String vehicleModel;
  final int vehicleModelYear;
  final RegistrationOwnerType registrationOwnerType;
  final bool hasVehicleUseAuthorization;
  final String? vehicleTaxiStandName;
  final bool informationAccuracyAccepted;
  final bool documentValidityNotificationAccepted;
  final bool documentProcessingNoticeAccepted;
  final bool kvkkNoticeAccepted;
  final bool termsAccepted;
  final bool marketingConsent;
  final String? rejectionReasonCode;
}

final class DriverApplicationReviewDocument {
  const DriverApplicationReviewDocument({
    required this.documentType,
    required this.reviewStatus,
    this.reviewedAt,
    this.rejectionReasonCode,
    required this.contentType,
    required this.sizeBytes,
  });
  final DriverDocumentType documentType;
  final DocumentReviewStatus reviewStatus;
  final DateTime? reviewedAt;
  final String? rejectionReasonCode;
  final String contentType;
  final int sizeBytes;
}

final class DriverApplicationReviewDetails {
  DriverApplicationReviewDetails({
    required this.reviewContext,
    required this.application,
    required List<DriverApplicationReviewDocument> documents,
  }) : documents = UnmodifiableListView(documents);
  final DriverApplicationReviewContext reviewContext;
  final DriverApplicationReviewApplication application;
  final List<DriverApplicationReviewDocument> documents;
}
