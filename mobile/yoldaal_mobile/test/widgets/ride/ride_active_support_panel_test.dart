import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_support_gateway.dart';
import 'package:yoldaal_mobile/widgets/ride/ride_active_support_panel.dart';

void main() {
  testWidgets(
    'active report uses five Turkish labels and submits optional note',
    (tester) async {
      final gateway = _Gateway();
      var requestIdCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RideActiveSupportPanel(
                rideId: 'ride_1',
                gateway: gateway,
                requestIdGenerator: () {
                  requestIdCalls += 1;
                  return 'active_support_request_1234567890';
                },
              ),
            ),
          ),
        ),
      );

      final submit = find.byKey(
        const ValueKey('ride-active-support-submit-ride_1'),
      );

      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('ride-active-support-category-ride_1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('G\u00FCvenlik'), findsOneWidget);
      expect(find.text('Davran\u0131\u015F / ileti\u015Fim'), findsOneWidget);
      expect(find.text('Yolculuk / rota sorunu'), findsOneWidget);
      expect(find.text('Teknik sorun'), findsOneWidget);
      expect(find.text('Unutulan e\u015Fya'), findsOneWidget);
      expect(find.text('\u00DCcret'), findsNothing);

      await tester.tap(find.text('G\u00FCvenlik').last);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('ride-active-support-safety-warning-ride_1')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('ride-active-support-note-ride_1')),
        '  Kisa guvenlik aciklamasi.  ',
      );

      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(requestIdCalls, 1);
      expect(gateway.calls, [
        const _Call(
          rideId: 'ride_1',
          category: 'safety',
          requestId: 'active_support_request_1234567890',
          note: 'Kisa guvenlik aciklamasi.',
        ),
      ]);
      expect(find.text("Bildiriminiz YoldaAl'a iletildi."), findsOneWidget);
    },
  );

  testWidgets('lost item category shows item description helper', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RideActiveSupportPanel(
              rideId: 'ride_lost',
              gateway: _Gateway(),
              requestIdGenerator: () => 'active_support_lost_1234567890',
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('ride-active-support-category-ride_lost')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unutulan e\u015Fya').last);
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('ride-active-support-lost-item-help-ride_lost'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ride-active-support-note-ride_lost')),
      findsOneWidget,
    );
  });

  testWidgets('failed retry preserves same request id for same payload', (
    tester,
  ) async {
    final gateway = _Gateway()..failuresRemaining = 1;
    var requestIdCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RideActiveSupportPanel(
              rideId: 'ride_2',
              gateway: gateway,
              requestIdGenerator: () {
                requestIdCalls += 1;
                return 'active_support_retry_1234567890';
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('ride-active-support-category-ride_2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yolculuk / rota sorunu').last);
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('ride-active-support-note-ride_2')),
      'Ayni aciklama',
    );

    final submit = find.byKey(
      const ValueKey('ride-active-support-submit-ride_2'),
    );

    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(requestIdCalls, 1);
    expect(gateway.calls, [
      const _Call(
        rideId: 'ride_2',
        category: 'route',
        requestId: 'active_support_retry_1234567890',
        note: 'Ayni aciklama',
      ),
      const _Call(
        rideId: 'ride_2',
        category: 'route',
        requestId: 'active_support_retry_1234567890',
        note: 'Ayni aciklama',
      ),
    ]);
  });

  testWidgets('payload change after failure generates a new request id', (
    tester,
  ) async {
    final gateway = _Gateway()..failuresRemaining = 1;
    var requestIdCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RideActiveSupportPanel(
              rideId: 'ride_change',
              gateway: gateway,
              requestIdGenerator: () =>
                  'active_support_change_${++requestIdCalls}_1234567890',
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('ride-active-support-category-ride_change')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teknik sorun').last);
    await tester.pump();

    final note = find.byKey(
      const ValueKey('ride-active-support-note-ride_change'),
    );
    final submit = find.byKey(
      const ValueKey('ride-active-support-submit-ride_change'),
    );

    await tester.enterText(note, 'Ilk aciklama');
    await tester.tap(submit);
    await tester.pumpAndSettle();

    await tester.enterText(note, 'Degisen aciklama');
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(requestIdCalls, 2);
    expect(gateway.calls[0].requestId, isNot(gateway.calls[1].requestId));
    expect(gateway.calls[1].note, 'Degisen aciklama');
  });

  testWidgets('double submit is blocked while request is in flight', (
    tester,
  ) async {
    final gateway = _PendingGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RideActiveSupportPanel(
              rideId: 'ride_3',
              gateway: gateway,
              requestIdGenerator: () => 'active_support_pending_1234567890',
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('ride-active-support-category-ride_3')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teknik sorun').last);
    await tester.pump();

    final submit = find.byKey(
      const ValueKey('ride-active-support-submit-ride_3'),
    );

    await tester.tap(submit);
    await tester.pump();

    expect(gateway.calls, 1);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    gateway.complete();
    await tester.pumpAndSettle();

    expect(gateway.calls, 1);
    expect(find.text("Bildiriminiz YoldaAl'a iletildi."), findsOneWidget);
  });
}

class _Call {
  const _Call({
    required this.rideId,
    required this.category,
    required this.requestId,
    required this.note,
  });

  final String rideId;
  final String category;
  final String requestId;
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is _Call &&
      other.rideId == rideId &&
      other.category == category &&
      other.requestId == requestId &&
      other.note == note;

  @override
  int get hashCode => Object.hash(rideId, category, requestId, note);
}

class _Gateway implements RideActiveSupportGateway {
  final calls = <_Call>[];
  int failuresRemaining = 0;

  @override
  Future<RideSupportCaseResult> createActiveCase({
    required String rideId,
    required String category,
    required String requestId,
    String? note,
  }) async {
    calls.add(
      _Call(
        rideId: rideId,
        category: category,
        requestId: requestId,
        note: note,
      ),
    );

    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const RideGatewayException('unavailable');
    }

    return RideSupportCaseResult(
      rideId: rideId,
      caseId: 'case_${calls.length}',
      category: category,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
    );
  }
}

class _PendingGateway implements RideActiveSupportGateway {
  final _completer = Completer<RideSupportCaseResult>();
  int calls = 0;

  @override
  Future<RideSupportCaseResult> createActiveCase({
    required String rideId,
    required String category,
    required String requestId,
    String? note,
  }) {
    calls += 1;
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      RideSupportCaseResult(
        rideId: 'ride_3',
        caseId: 'case_pending',
        category: 'technical',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
      ),
    );
  }
}
