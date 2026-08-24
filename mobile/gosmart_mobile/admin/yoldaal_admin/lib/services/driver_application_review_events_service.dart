import '../application/ports.dart';
import '../domain/driver_application.dart';
import '../domain/driver_application_review_event.dart';

final class DriverApplicationReviewEventsService
    implements DriverApplicationReviewEventsGateway {
  DriverApplicationReviewEventsService(this._invoker);
  final AdminCallableInvoker _invoker;

  @override
  Future<DriverApplicationReviewEventsPage> listReviewEvents({
    required String applicationId,
    int pageSize = 20,
    DriverApplicationReviewEventsCursor? cursor,
  }) async {
    final id = _text(applicationId);
    if (pageSize < 1 || pageSize > 50) throw RangeError.range(pageSize, 1, 50);
    final payload = <String, Object?>{
      'applicationId': id,
      'pageSize': pageSize,
      if (cursor != null)
        'cursor': <String, Object?>{
          'createdAtMillis': cursor.occurredAt.millisecondsSinceEpoch,
          'eventId': cursor.eventId,
        },
    };
    return _parsePage(
      await _invoker.call(
        functionName: 'listDriverApplicationReviewEvents',
        payload: payload,
      ),
    );
  }

  DriverApplicationReviewEventsPage _parsePage(Object? raw) {
    final map = _map(raw);
    final rawItems = map['items'];
    if (rawItems is! List) {
      throw const FormatException('Invalid timeline items');
    }
    final items = rawItems
        .map((item) => _parseEvent(_map(item)))
        .toList(growable: false);
    final rawCursor = map['nextCursor'];
    return DriverApplicationReviewEventsPage(
      items: items,
      nextCursor: rawCursor == null ? null : _parseCursor(_map(rawCursor)),
    );
  }

  DriverApplicationReviewEvent _parseEvent(Map<String, Object?> map) =>
      DriverApplicationReviewEvent(
        type: _enum(DriverApplicationReviewEventType.values, map['type']),
        occurredAt: _date(map['occurredAtMillis']),
        documentType: _nullableEnum(
          DriverDocumentType.values,
          map['documentType'],
        ),
        decision: _nullableEnum(
          DriverApplicationReviewEventDecision.values,
          map['decision'],
        ),
        reason: _reason(map['reasonCode']),
      );

  DriverApplicationReviewEventsCursor _parseCursor(Map<String, Object?> map) =>
      DriverApplicationReviewEventsCursor(
        occurredAt: _date(map['createdAtMillis']),
        eventId: _text(map['eventId']),
      );

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('Invalid timeline response');
    if (value.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid timeline response');
    }
    return value.cast<String, Object?>();
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Invalid text');
    }
    return value.trim();
  }

  static DateTime _date(Object? value) {
    if (value is! int || value < 0) throw const FormatException('Invalid time');
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  static T _enum<T extends Enum>(List<T> values, Object? value) {
    if (value is! String) throw const FormatException('Invalid enum');
    return values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw const FormatException('Unknown enum'),
    );
  }

  static T? _nullableEnum<T extends Enum>(List<T> values, Object? value) =>
      value == null ? null : _enum(values, value);
  static DriverApplicationReviewEventReason? _reason(Object? value) {
    if (value == null) return null;
    if (value is! String) throw const FormatException('Invalid reason');
    return DriverApplicationReviewEventReason.values.firstWhere(
      (item) => item.wireValue == value,
      orElse: () => throw const FormatException('Unknown reason'),
    );
  }
}
