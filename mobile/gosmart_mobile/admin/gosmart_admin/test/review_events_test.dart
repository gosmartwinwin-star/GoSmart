import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_admin/application/ports.dart';
import 'package:gosmart_admin/controllers/driver_application_review_events_controller.dart';
import 'package:gosmart_admin/core/admin_exceptions.dart';
import 'package:gosmart_admin/domain/driver_application.dart';
import 'package:gosmart_admin/domain/driver_application_review_event.dart';
import 'package:gosmart_admin/services/driver_application_review_events_service.dart';
import 'package:gosmart_admin/widgets/review_events_timeline.dart';

void main() {
  group('review events service', () {
    test('uses exact callable and minimal default payload', () async {
      final invoker = _Invoker(_response());
      final page = await DriverApplicationReviewEventsService(
        invoker,
      ).listReviewEvents(applicationId: 'app-1');
      expect(invoker.functionName, 'listDriverApplicationReviewEvents');
      expect(invoker.payload, {'applicationId': 'app-1', 'pageSize': 20});
      for (final key in [
        'admin',
        'uid',
        'documentSetId',
        'submissionVersion',
        'offset',
      ]) {
        expect(invoker.payload, isNot(contains(key)));
      }
      expect(page.items, hasLength(1));
    });

    test('cursor contains only millis and internal event id', () async {
      final invoker = _Invoker(_response());
      final cursor = DriverApplicationReviewEventsCursor(
        occurredAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        eventId: 'event-secret',
      );
      await DriverApplicationReviewEventsService(
        invoker,
      ).listReviewEvents(applicationId: 'app-1', cursor: cursor);
      expect(invoker.payload['cursor'], {
        'createdAtMillis': 1000,
        'eventId': 'event-secret',
      });
      expect(cursor.toString(), isNot(contains('event-secret')));
    });

    test('parses UTC event and controlled labels', () async {
      final page = await DriverApplicationReviewEventsService(
        _Invoker(_response()),
      ).listReviewEvents(applicationId: 'app-1');
      final event = page.items.single;
      expect(event.occurredAt.isUtc, isTrue);
      expect(event.type, DriverApplicationReviewEventType.documentApproved);
      expect(event.documentType, DriverDocumentType.criminalRecord);
      expect(event.decision, DriverApplicationReviewEventDecision.approve);
      expect(
        event.reason,
        DriverApplicationReviewEventReason.unreadableDocument,
      );
    });

    test('parses resubmission with safe Turkish label', () async {
      final response = _response();
      final item = (response['items']! as List).single as Map<String, Object?>;
      item
        ..['type'] = 'applicationResubmitted'
        ..['documentType'] = null
        ..['decision'] = null
        ..['reasonCode'] = null
        ..['documentSetId'] = 'internal-set'
        ..['submissionVersion'] = 3
        ..['requestId'] = 'internal-request';
      final event = (await DriverApplicationReviewEventsService(
        _Invoker(response),
      ).listReviewEvents(applicationId: 'app-1')).items.single;
      expect(
        event.type,
        DriverApplicationReviewEventType.applicationResubmitted,
      );
      expect(event.type.label, 'Başvuru belgeleri yeniden gönderildi');
      expect(event.documentType, isNull);
      expect(event.decision, isNull);
      expect(event.reason, isNull);
      expect(event.toString(), isNot(contains('internal-')));
    });

    for (final badMillis in <Object?>[true, 1.2, -1, null]) {
      test('rejects invalid event millis $badMillis', () async {
        final response = _response();
        ((response['items']! as List).single as Map)['occurredAtMillis'] =
            badMillis;
        expect(
          DriverApplicationReviewEventsService(
            _Invoker(response),
          ).listReviewEvents(applicationId: 'app-1'),
          throwsFormatException,
        );
      });
    }

    test('rejects unknown wire enums instead of exposing raw values', () async {
      for (final entry in {
        'type': 'rawEvent',
        'documentType': 'rawDocument',
        'decision': 'rawDecision',
        'reasonCode': 'rawReason',
      }.entries) {
        final response = _response();
        ((response['items']! as List).single as Map)[entry.key] = entry.value;
        expect(
          DriverApplicationReviewEventsService(
            _Invoker(response),
          ).listReviewEvents(applicationId: 'app-1'),
          throwsFormatException,
        );
      }
    });

    test('ignores identity, storage and PII response extras', () async {
      final response = _response();
      ((response['items']! as List).single as Map<String, Object?>).addAll({
        'reviewerUid': 'uid-secret',
        'adminEmail': 'admin-secret',
        'documentSetId': 'set-secret',
        'storagePath': 'path-secret',
        'signedUrl': 'url-secret',
        'fullName': 'person-secret',
      });
      final event = (await DriverApplicationReviewEventsService(
        _Invoker(response),
      ).listReviewEvents(applicationId: 'app-1')).items.single;
      final text = event.toString();
      for (final secret in [
        'uid-secret',
        'admin-secret',
        'set-secret',
        'path-secret',
        'url-secret',
        'person-secret',
      ]) {
        expect(text, isNot(contains(secret)));
      }
    });

    test('validates next cursor strictly', () async {
      final response = _response();
      response['nextCursor'] = {'createdAtMillis': 1000, 'eventId': 'event-a'};
      final cursor = (await DriverApplicationReviewEventsService(
        _Invoker(response),
      ).listReviewEvents(applicationId: 'app-1')).nextCursor!;
      expect(cursor.occurredAt.isUtc, isTrue);
      expect(cursor.toString(), isNot(contains('event-a')));
      response['nextCursor'] = {'createdAtMillis': true, 'eventId': ''};
      expect(
        DriverApplicationReviewEventsService(
          _Invoker(response),
        ).listReviewEvents(applicationId: 'app-1'),
        throwsFormatException,
      );
    });
  });

  group('review events controller', () {
    test(
      'loads, appends without duplicates and clears sensitive state',
      () async {
        final gateway = _EventsGateway();
        final controller = DriverApplicationReviewEventsController(gateway);
        await controller.loadInitial('app-1');
        expect(controller.items, hasLength(1));
        await controller.loadMore();
        expect(controller.items, hasLength(1));
        controller.clearSensitiveState();
        expect(controller.items, isEmpty);
        expect(controller.nextCursor, isNull);
      },
    );

    test('new application immediately replaces old state', () async {
      final gateway = _EventsGateway();
      final controller = DriverApplicationReviewEventsController(gateway);
      await controller.loadInitial('app-1');
      await controller.loadInitial('app-2');
      expect(controller.currentApplicationId, 'app-2');
      expect(gateway.applicationIds, ['app-1', 'app-2']);
    });

    test('load more error preserves existing items', () async {
      final gateway = _EventsGateway(failMore: true);
      final controller = DriverApplicationReviewEventsController(gateway);
      await controller.loadInitial('app-1');
      await controller.loadMore();
      expect(controller.items, hasLength(1));
      expect(controller.errorMessage, isNotNull);
    });

    test('auth error clears state and invokes callback', () async {
      var authFailures = 0;
      final controller = DriverApplicationReviewEventsController(
        _EventsGateway(authError: true),
        handleAuthFailure: () async => authFailures++,
      );
      await controller.loadInitial('app-1');
      expect(controller.items, isEmpty);
      expect(controller.currentApplicationId, isNull);
      expect(authFailures, 1);
    });

    test(
      'dispose redacts cursor and prevents later state publication',
      () async {
        final completer = Completer<DriverApplicationReviewEventsPage>();
        final controller = DriverApplicationReviewEventsController(
          _PendingGateway(completer),
        );
        final future = controller.loadInitial('app-1');
        controller.dispose();
        completer.complete(_page());
        await future;
        expect(controller.toString(), isNot(contains('event-secret')));
      },
    );
  });

  testWidgets('timeline renders safe Turkish labels and no raw fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = DriverApplicationReviewEventsController(
      _EventsGateway(),
    );
    await controller.loadInitial('app-1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverApplicationReviewEventsTimeline(controller: controller),
        ),
      ),
    );
    expect(find.text('İnceleme Geçmişi'), findsOneWidget);
    expect(find.text('Belge onaylandı'), findsOneWidget);
    expect(find.text('Adli Sicil Kaydı'), findsOneWidget);
    expect(find.text('Onaylandı'), findsOneWidget);
    expect(find.text('Belge okunamıyor.'), findsOneWidget);
    expect(find.text('Daha Fazla Göster'), findsOneWidget);
    for (final raw in [
      'documentApproved',
      'criminalRecord',
      'approve',
      'unreadable_document',
      'event-secret',
      'uid-secret',
      'documentSetId',
      'storagePath',
      'signedUrl',
    ]) {
      expect(find.textContaining(raw), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline has explicit loading, empty and error states', (
    tester,
  ) async {
    final pending = Completer<DriverApplicationReviewEventsPage>();
    final loading = DriverApplicationReviewEventsController(
      _PendingGateway(pending),
    );
    unawaited(loading.loadInitial('app-1'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverApplicationReviewEventsTimeline(controller: loading),
        ),
      ),
    );
    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.semanticsLabel, 'İnceleme geçmişi yükleniyor');
    pending.complete(
      DriverApplicationReviewEventsPage(items: const [], nextCursor: null),
    );
    await tester.pump();
    expect(
      find.text('Bu başvuru için henüz inceleme geçmişi bulunmuyor.'),
      findsOneWidget,
    );
    final failed = DriverApplicationReviewEventsController(
      _EventsGateway(failInitial: true),
    );
    await failed.loadInitial('app-1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverApplicationReviewEventsTimeline(controller: failed),
        ),
      ),
    );
    expect(find.text('İnceleme geçmişi şu anda yüklenemedi.'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });
}

Map<String, Object?> _response() => {
  'items': [
    <String, Object?>{
      'type': 'documentApproved',
      'occurredAtMillis': 1000,
      'documentType': 'criminalRecord',
      'decision': 'approve',
      'reasonCode': 'unreadable_document',
    },
  ],
  'nextCursor': null,
};

final class _Invoker implements AdminCallableInvoker {
  _Invoker(this.response);
  final Object? response;
  String? functionName;
  Map<String, Object?> payload = const {};
  @override
  Future<Object?> call({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    this.functionName = functionName;
    this.payload = payload;
    return response;
  }
}

DriverApplicationReviewEvent _event() => DriverApplicationReviewEvent(
  type: DriverApplicationReviewEventType.documentApproved,
  occurredAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
  documentType: DriverDocumentType.criminalRecord,
  decision: DriverApplicationReviewEventDecision.approve,
  reason: DriverApplicationReviewEventReason.unreadableDocument,
);
DriverApplicationReviewEventsCursor _cursor() =>
    DriverApplicationReviewEventsCursor(
      occurredAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      eventId: 'event-secret',
    );
DriverApplicationReviewEventsPage _page({bool cursor = false}) =>
    DriverApplicationReviewEventsPage(
      items: [_event()],
      nextCursor: cursor ? _cursor() : null,
    );

final class _EventsGateway implements DriverApplicationReviewEventsGateway {
  _EventsGateway({
    this.failInitial = false,
    this.failMore = false,
    this.authError = false,
  });
  final bool failInitial;
  final bool failMore;
  final bool authError;
  final List<String> applicationIds = [];
  int calls = 0;
  @override
  Future<DriverApplicationReviewEventsPage> listReviewEvents({
    required String applicationId,
    int pageSize = 20,
    DriverApplicationReviewEventsCursor? cursor,
  }) async {
    calls++;
    applicationIds.add(applicationId);
    if (authError) {
      throw const AdminPanelException(
        'permission-denied',
        reason: 'admin_access_required',
      );
    }
    if ((cursor == null && failInitial) || (cursor != null && failMore)) {
      throw const AdminPanelException(
        'unavailable',
        reason: 'driver_application_review_events_failed',
      );
    }
    return _page(cursor: cursor == null);
  }
}

final class _PendingGateway implements DriverApplicationReviewEventsGateway {
  _PendingGateway(this.completer);
  final Completer<DriverApplicationReviewEventsPage> completer;
  @override
  Future<DriverApplicationReviewEventsPage> listReviewEvents({
    required String applicationId,
    int pageSize = 20,
    DriverApplicationReviewEventsCursor? cursor,
  }) => completer.future;
}
