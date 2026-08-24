import 'dart:collection';

import 'driver_application_document.dart';
import 'driver_application_document_status.dart';
import 'driver_application_document_type.dart';
import 'driver_application_status.dart';
import 'driver_work_type.dart';
import 'registration_owner_type.dart';

class DriverApplication {
  final String id;
  final String authUserId;
  final String verifiedPhoneNumber;
  final String fullName;
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
  final DriverApplicationStatus status;
  final DateTime submittedAt;
  final DateTime updatedAt;
  final DateTime? reviewedAt;
  final String? rejectionReasonCode;
  final int submissionVersion;
  final String documentSetId;
  final bool informationAccuracyAccepted;
  final bool documentValidityNotificationAccepted;
  final bool documentProcessingNoticeAccepted;
  final bool kvkkNoticeAccepted;
  final bool termsAccepted;
  final bool marketingConsent;
  final List<DriverApplicationDocument> documents;

  DriverApplication({
    required this.id,
    required this.authUserId,
    required this.verifiedPhoneNumber,
    required this.fullName,
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
    required this.status,
    required this.submittedAt,
    required this.updatedAt,
    this.reviewedAt,
    this.rejectionReasonCode,
    required this.submissionVersion,
    required this.documentSetId,
    required this.informationAccuracyAccepted,
    required this.documentValidityNotificationAccepted,
    required this.documentProcessingNoticeAccepted,
    required this.kvkkNoticeAccepted,
    required this.termsAccepted,
    this.marketingConsent = false,
    required List<DriverApplicationDocument> documents,
  }) : documents = UnmodifiableListView(documents) {
    if (id.trim().isEmpty || authUserId.trim().isEmpty || id != authUserId) {
      throw ArgumentError('Başvuru ve kullanıcı kimliği geçersiz.');
    }
    if (verifiedPhoneNumber.trim().isEmpty ||
        fullName.trim().isEmpty ||
        vehiclePlate.trim().isEmpty ||
        vehicleBrand.trim().isEmpty ||
        vehicleModel.trim().isEmpty) {
      throw ArgumentError('Zorunlu başvuru alanı boş olamaz.');
    }
    if (email != null && email!.trim().isEmpty) {
      throw ArgumentError.value(email, 'email');
    }
    if (vehicleModelYear <= 0 || submissionVersion <= 0) {
      throw ArgumentError('Yıl ve başvuru sürümü pozitif olmalıdır.');
    }
    if (documentSetId.trim().isEmpty) {
      throw ArgumentError.value(documentSetId, 'documentSetId');
    }
    if (registrationOwnerType != RegistrationOwnerType.applicant &&
        !hasVehicleUseAuthorization) {
      throw ArgumentError('Araç kullanım yetkisi beyanı zorunludur.');
    }
    if (updatedAt.isBefore(submittedAt) ||
        (reviewedAt?.isBefore(submittedAt) ?? false)) {
      throw ArgumentError('Başvuru zamanları geçersiz.');
    }
    if (!informationAccuracyAccepted ||
        !documentValidityNotificationAccepted ||
        !documentProcessingNoticeAccepted ||
        !kvkkNoticeAccepted ||
        !termsAccepted) {
      throw ArgumentError('Zorunlu beyanların tamamı kabul edilmelidir.');
    }
    if (documents.map((item) => item.type).toSet().length != documents.length) {
      throw ArgumentError('Belge türleri tekrarlanamaz.');
    }
    if (status == DriverApplicationStatus.pendingReview &&
        (!hasAllRequiredDocuments ||
            documents.any(
              (item) =>
                  item.status.index <
                  DriverApplicationDocumentStatus.pendingReview.index,
            ))) {
      throw ArgumentError('İnceleme başvurusunda yedi belge zorunludur.');
    }
  }

  bool get isPendingReview => status == DriverApplicationStatus.pendingReview;
  bool get isApproved => status == DriverApplicationStatus.approved;
  bool get canResubmit =>
      status == DriverApplicationStatus.rejected ||
      status == DriverApplicationStatus.withdrawn;
  bool get hasAllRequiredDocuments => DriverApplicationDocumentType.values
      .every((type) => documents.any((document) => document.type == type));
}
