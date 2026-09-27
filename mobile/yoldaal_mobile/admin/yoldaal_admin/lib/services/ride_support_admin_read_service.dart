import '../application/ride_support_admin_ports.dart';
import '../domain/ride_support_case.dart';
import '../application/ports.dart';

final class RideSupportAdminReadService
    implements RideSupportAdminReadGateway, RideSupportAdminTransitionGateway {
  RideSupportAdminReadService(this._invoker);
  final AdminCallableInvoker _invoker;

  @override
  Future<RideSupportCasePage> list({
    int pageSize = 20,
    RideSupportCaseCursor? cursor,
  }) async {
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50);
    }
    final payload = <String, Object?>{
      'pageSize': pageSize,
      if (cursor != null)
        'cursor': <String, Object?>{
          'createdAtMillis': cursor.createdAt.millisecondsSinceEpoch,
          'rideId': cursor.rideId,
          'caseId': cursor.caseId,
        },
    };
    return _parsePage(
      await _invoker.call(
        functionName: 'listRideSupportCasesForAdmin',
        payload: payload,
      ),
    );
  }

  @override
  Future<RideSupportCaseTransitionResult> transition({
    required String rideId,
    required String caseId,
    required RideSupportCaseStatus targetStatus,
    required DateTime expectedUpdatedAt,
    required String requestId,
  }) async {
    if (targetStatus == RideSupportCaseStatus.newCase) {
      throw ArgumentError.value(targetStatus, 'targetStatus');
    }
    final raw = await _invoker.call(
      functionName: 'transitionRideSupportCaseForAdmin',
      payload: <String, Object?>{
        'rideId': _text(rideId),
        'caseId': _text(caseId),
        'targetStatus': targetStatus.wireName,
        'expectedUpdatedAtMillis': expectedUpdatedAt.millisecondsSinceEpoch,
        'requestId': _text(requestId),
      },
    );
    final map = _map(raw);
    final idempotent = map['idempotent'];
    if (idempotent is! bool) {
      throw const FormatException('Invalid transition response');
    }
    return RideSupportCaseTransitionResult(
      status: RideSupportCaseStatus.fromWire(_text(map['status'])),
      updatedAt: _date(map['updatedAtMillis']),
      idempotent: idempotent,
    );
  }

  RideSupportCasePage _parsePage(Object? raw) {
    final map = _map(raw);
    final rawItems = map['items'];
    if (rawItems is! List) throw const FormatException('Invalid items');

    final items = rawItems
        .map((rawItem) {
          final item = _map(rawItem);
          return RideSupportCaseSummary(
            rideId: _text(item['rideId']),
            caseId: _text(item['caseId']),
            reporterRole: RideSupportReporterRole.fromWire(
              _text(item['reporterRole']),
            ),
            reporterId: _text(item['reporterId']),
            counterpartyId: _nullableText(item['counterpartyId']),
            category: RideSupportCategory.fromWire(_text(item['category'])),
            reporterNote: _nullableText(item['reporterNote']),
            status: RideSupportCaseStatus.fromWire(_text(item['status'])),
            createdAt: _date(item['createdAtMillis']),
            updatedAt: _date(item['updatedAtMillis']),
          );
        })
        .toList(growable: false);

    final rawCursor = map['nextCursor'];
    return RideSupportCasePage(
      items: items,
      nextCursor: rawCursor == null ? null : _parseCursor(rawCursor),
    );
  }

  RideSupportCaseCursor _parseCursor(Object? raw) {
    final map = _map(raw);
    return RideSupportCaseCursor(
      createdAt: _date(map['createdAtMillis']),
      rideId: _text(map['rideId']),
      caseId: _text(map['caseId']),
    );
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('Invalid response');
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Invalid text');
    }
    return value.trim();
  }

  static String? _nullableText(Object? value) =>
      value == null ? null : _text(value);

  static DateTime _date(Object? value) {
    if (value is! int || value < 0) {
      throw const FormatException('Invalid date');
    }
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
}
