import '../application/ports.dart';
import '../core/admin_exceptions.dart';
import '../domain/driver_application.dart';

final class DriverApplicationAdminReadService
    implements DriverApplicationAdminReadGateway {
  DriverApplicationAdminReadService(this._invoker);
  final AdminCallableInvoker _invoker;

  @override
  Future<DriverApplicationReviewPage> list({
    required DriverApplicationReviewStatus status,
    int pageSize = 20,
    DriverApplicationReviewCursor? cursor,
  }) async {
    if (pageSize < 1 || pageSize > 50) throw RangeError.range(pageSize, 1, 50);
    final payload = <String, Object?>{
      'status': status.name,
      'pageSize': pageSize,
      if (cursor != null)
        'cursor': <String, Object?>{
          'submittedAtMillis': cursor.submittedAt.millisecondsSinceEpoch,
          'applicationId': cursor.applicationId,
        },
    };
    return _parsePage(
      await _invoker.call(
        functionName: 'listDriverApplicationsForReview',
        payload: payload,
      ),
    );
  }

  @override
  Future<DriverApplicationReviewDetails> getDetails({
    required String applicationId,
  }) async {
    final id = _text(applicationId, 'applicationId');
    return _parseDetails(
      await _invoker.call(
        functionName: 'getDriverApplicationReviewDetails',
        payload: <String, Object?>{'applicationId': id},
      ),
    );
  }

  DriverApplicationReviewPage _parsePage(Object? raw) {
    final map = _map(raw);
    final rawItems = map['items'];
    if (rawItems is! List) throw const FormatException('Invalid items');
    final items = rawItems
        .map((item) {
          final value = _map(item);
          return DriverApplicationReviewSummary(
            applicationId: _text(value['applicationId'], 'applicationId'),
            status: _enum(
              DriverApplicationReviewStatus.values,
              value['status'],
            ),
            submittedAt: _date(value['submittedAtMillis']),
            updatedAt: _date(value['updatedAtMillis']),
            submissionVersion: _positiveInt(value['submissionVersion']),
            workType: _enum(DriverWorkType.values, value['workType']),
            vehicleBrand: _text(value['vehicleBrand'], 'vehicleBrand'),
            vehicleModel: _text(value['vehicleModel'], 'vehicleModel'),
            vehicleModelYear: _positiveInt(value['vehicleModelYear']),
            registrationOwnerType: _enum(
              RegistrationOwnerType.values,
              value['registrationOwnerType'],
            ),
          );
        })
        .toList(growable: false);
    final rawCursor = map['nextCursor'];
    final cursor = rawCursor == null ? null : _parseCursor(rawCursor);
    return DriverApplicationReviewPage(items: items, nextCursor: cursor);
  }

  DriverApplicationReviewCursor _parseCursor(Object? raw) {
    final map = _map(raw);
    return DriverApplicationReviewCursor(
      submittedAt: _date(map['submittedAtMillis']),
      applicationId: _text(map['applicationId'], 'applicationId'),
    );
  }

  DriverApplicationReviewDetails _parseDetails(Object? raw) {
    final map = _map(raw);
    final contextMap = _map(map['reviewContext']);
    final context = DriverApplicationReviewContext(
      submissionVersion: _positiveInt(contextMap['submissionVersion']),
      documentSetId: _text(contextMap['documentSetId'], 'documentSetId'),
    );
    final application = _parseApplication(_map(map['application']));
    final rawDocuments = map['documents'];
    if (rawDocuments is! List ||
        rawDocuments.length != DriverDocumentType.values.length) {
      throw const FormatException('Invalid documents');
    }
    final documents = rawDocuments
        .map((item) => _parseDocument(_map(item)))
        .toList(growable: false);
    if (documents.map((item) => item.documentType).toSet().length !=
        DriverDocumentType.values.length) {
      throw const FormatException('Duplicate documents');
    }
    return DriverApplicationReviewDetails(
      reviewContext: context,
      application: application,
      documents: documents,
    );
  }

  DriverApplicationReviewApplication _parseApplication(Map<String, Object?> m) {
    return DriverApplicationReviewApplication(
      applicationId: _text(m['applicationId'], 'applicationId'),
      status: _enum(DriverApplicationReviewStatus.values, m['status']),
      submittedAt: _date(m['submittedAtMillis']),
      updatedAt: _date(m['updatedAtMillis']),
      reviewedAt: _nullableDate(m['reviewedAtMillis']),
      submissionVersion: _positiveInt(m['submissionVersion']),
      fullName: _text(m['fullName'], 'fullName'),
      verifiedPhoneNumber: _text(m['verifiedPhoneNumber'], 'phone'),
      email: _nullableText(m['email']),
      driverTaxiStandName: _nullableText(m['driverTaxiStandName']),
      driverTaxiStandAddress: _nullableText(m['driverTaxiStandAddress']),
      workType: _enum(DriverWorkType.values, m['workType']),
      vehiclePlate: _text(m['vehiclePlate'], 'vehiclePlate'),
      vehicleBrand: _text(m['vehicleBrand'], 'vehicleBrand'),
      vehicleModel: _text(m['vehicleModel'], 'vehicleModel'),
      vehicleModelYear: _positiveInt(m['vehicleModelYear']),
      registrationOwnerType: _enum(
        RegistrationOwnerType.values,
        m['registrationOwnerType'],
      ),
      hasVehicleUseAuthorization: _boolean(m['hasVehicleUseAuthorization']),
      vehicleTaxiStandName: _nullableText(m['vehicleTaxiStandName']),
      informationAccuracyAccepted: _boolean(m['informationAccuracyAccepted']),
      documentValidityNotificationAccepted: _boolean(
        m['documentValidityNotificationAccepted'],
      ),
      documentProcessingNoticeAccepted: _boolean(
        m['documentProcessingNoticeAccepted'],
      ),
      kvkkNoticeAccepted: _boolean(m['kvkkNoticeAccepted']),
      termsAccepted: _boolean(m['termsAccepted']),
      marketingConsent: _boolean(m['marketingConsent']),
      rejectionReasonCode: _nullableText(m['rejectionReasonCode']),
    );
  }

  DriverApplicationReviewDocument _parseDocument(Map<String, Object?> m) {
    return DriverApplicationReviewDocument(
      documentType: _enum(DriverDocumentType.values, m['documentType']),
      reviewStatus: _enum(DocumentReviewStatus.values, m['reviewStatus']),
      reviewedAt: _nullableDate(m['reviewedAtMillis']),
      rejectionReasonCode: _nullableText(m['rejectionReasonCode']),
      contentType: _text(m['contentType'], 'contentType'),
      sizeBytes: _positiveInt(m['sizeBytes']),
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('Invalid response');
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static int _positiveInt(Object? value) {
    if (value is! int || value < 1) throw const FormatException('Invalid int');
    return value;
  }

  static int _nonNegativeInt(Object? value) {
    if (value is! int || value < 0) throw const FormatException('Invalid int');
    return value;
  }

  static DateTime _date(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch(_nonNegativeInt(value), isUtc: true);

  static DateTime? _nullableDate(Object? value) =>
      value == null ? null : _date(value);

  static String _text(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid $field');
    }
    return value.trim();
  }

  static String? _nullableText(Object? value) =>
      value == null ? null : _text(value, 'text');

  static bool _boolean(Object? value) {
    if (value is! bool) throw const FormatException('Invalid bool');
    return value;
  }

  static T _enum<T extends Enum>(List<T> values, Object? value) {
    if (value is! String) throw const FormatException('Invalid enum');
    return values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw const FormatException('Unknown enum'),
    );
  }
}

AdminPanelException safeCallableFailure(String code, String? reason) =>
    AdminPanelException(code, reason: reason);
