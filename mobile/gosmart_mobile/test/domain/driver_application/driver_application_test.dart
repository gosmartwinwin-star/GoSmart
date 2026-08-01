import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_status.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_status.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_work_type.dart';
import 'package:gosmart_mobile/domain/driver_application/registration_owner_type.dart';

final now = DateTime.utc(2026);

DriverApplicationDocument document(DriverApplicationDocumentType type) =>
    DriverApplicationDocument(
      type: type,
      status: DriverApplicationDocumentStatus.pendingReview,
      storagePath: 'driverApplicationSubmissions/user-a/set-a/${type.name}',
      contentType: 'image/jpeg',
      sizeBytes: 1,
      uploadedAt: now,
      documentSetId: 'set-a',
      submissionVersion: 1,
    );

DriverApplication application({
  DriverApplicationStatus status = DriverApplicationStatus.pendingReview,
  RegistrationOwnerType owner = RegistrationOwnerType.applicant,
  bool authorization = false,
  bool marketing = false,
  bool terms = true,
  List<DriverApplicationDocument>? documents,
}) => DriverApplication(
  id: 'user-a',
  authUserId: 'user-a',
  verifiedPhoneNumber: '+905000000000',
  fullName: 'Ali Veli',
  workType: DriverWorkType.vehicleOwner,
  vehiclePlate: '06ABC123',
  vehicleBrand: 'Fiat',
  vehicleModel: 'Egea',
  vehicleModelYear: 2020,
  registrationOwnerType: owner,
  hasVehicleUseAuthorization: authorization,
  status: status,
  submittedAt: now,
  updatedAt: now,
  submissionVersion: 1,
  documentSetId: 'set-a',
  informationAccuracyAccepted: true,
  documentValidityNotificationAccepted: true,
  documentProcessingNoticeAccepted: true,
  kvkkNoticeAccepted: true,
  termsAccepted: terms,
  marketingConsent: marketing,
  documents:
      documents ?? DriverApplicationDocumentType.values.map(document).toList(),
);

void main() {
  test('applicant dışındaki sahipliklerde yetki beyanı zorunludur', () {
    expect(
      () => application(owner: RegistrationOwnerType.company),
      throwsArgumentError,
    );
    expect(
      () => application(
        owner: RegistrationOwnerType.otherIndividual,
        authorization: true,
      ),
      returnsNormally,
    );
  });

  test('beş zorunlu beyan gerekir fakat marketing false olabilir', () {
    expect(() => application(marketing: false), returnsNormally);
    expect(() => application(terms: false), throwsArgumentError);
  });

  test('eksik belge seti tamamlanmamıştır', () {
    final result = application(
      status: DriverApplicationStatus.rejected,
      documents: [document(DriverApplicationDocumentType.criminalRecord)],
    );
    expect(result.hasAllRequiredDocuments, isFalse);
  });

  test('yedi belgeyle pendingReview başvuru tamamdır', () {
    final result = application();
    expect(result.isPendingReview, isTrue);
    expect(result.hasAllRequiredDocuments, isTrue);
  });

  test('tekrarlanan belge tipi reddedilir', () {
    final item = document(DriverApplicationDocumentType.criminalRecord);
    expect(
      () => application(
        status: DriverApplicationStatus.rejected,
        documents: [item, item],
      ),
      throwsArgumentError,
    );
  });

  test('documents listesi immutable olur', () {
    expect(
      () => application().documents.add(
        document(DriverApplicationDocumentType.criminalRecord),
      ),
      throwsUnsupportedError,
    );
  });

  test('rejected ve withdrawn yeniden gönderilebilir', () {
    expect(
      application(status: DriverApplicationStatus.rejected).canResubmit,
      isTrue,
    );
    expect(
      application(status: DriverApplicationStatus.withdrawn).canResubmit,
      isTrue,
    );
  });
}
