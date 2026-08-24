import 'dart:collection';
import 'driver_application.dart';

enum DriverApplicationReviewEventType {
  applicationViewed('Başvuru görüntülendi'),
  documentViewed('Belge görüntülendi'),
  documentApproved('Belge onaylandı'),
  documentReuploadRequired('Belgenin yeniden yüklenmesi istendi'),
  applicationApproved('Başvuru onaylandı'),
  applicationRejected('Başvuru reddedildi'),
  applicationResubmitted('Başvuru belgeleri yeniden gönderildi'),
  unknownReviewEvent('İnceleme işlemi gerçekleştirildi');

  const DriverApplicationReviewEventType(this.label);
  final String label;
}

enum DriverApplicationReviewEventDecision {
  approve('Onaylandı'),
  requireReupload('Yeniden yükleme istendi'),
  reject('Reddedildi');

  const DriverApplicationReviewEventDecision(this.label);
  final String label;
}

enum DriverApplicationReviewEventReason {
  unreadableDocument('unreadable_document', 'Belge okunamıyor.'),
  incompleteDocument('incomplete_document', 'Belge eksik görünüyor.'),
  expiredDocument('expired_document', 'Belgenin geçerlilik süresi dolmuş.'),
  informationMismatch('information_mismatch', 'Belgedeki bilgiler eşleşmiyor.'),
  wrongDocument('wrong_document', 'Farklı bir belge yüklenmiş.'),
  unsupportedDocument('unsupported_document', 'Belge biçimi desteklenmiyor.'),
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
  ),
  documentReuploadRequired(
    'document_reupload_required',
    'Belgenin yeniden yüklenmesi gerekiyor.',
  );

  const DriverApplicationReviewEventReason(this.wireValue, this.label);
  final String wireValue;
  final String label;
}

final class DriverApplicationReviewEvent {
  const DriverApplicationReviewEvent({
    required this.type,
    required this.occurredAt,
    this.documentType,
    this.decision,
    this.reason,
  });
  final DriverApplicationReviewEventType type;
  final DateTime occurredAt;
  final DriverDocumentType? documentType;
  final DriverApplicationReviewEventDecision? decision;
  final DriverApplicationReviewEventReason? reason;
  String get safeKey =>
      '${type.name}|${occurredAt.microsecondsSinceEpoch}|'
      '${documentType?.name ?? ''}|${decision?.name ?? ''}|${reason?.name ?? ''}';
}

final class DriverApplicationReviewEventsCursor {
  DriverApplicationReviewEventsCursor({
    required this.occurredAt,
    required String eventId,
  }) : _eventId = eventId.trim() {
    if (!occurredAt.isUtc || _eventId.isEmpty) {
      throw const FormatException('Invalid review events cursor');
    }
  }
  final DateTime occurredAt;
  final String _eventId;
  String get eventId => _eventId;
  @override
  String toString() => 'DriverApplicationReviewEventsCursor(redacted)';
}

final class DriverApplicationReviewEventsPage {
  DriverApplicationReviewEventsPage({
    required List<DriverApplicationReviewEvent> items,
    required this.nextCursor,
  }) : items = UnmodifiableListView(items);
  final List<DriverApplicationReviewEvent> items;
  final DriverApplicationReviewEventsCursor? nextCursor;
}
