import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_support_gateway.dart';
import 'package:yoldaal_mobile/widgets/ride/ride_active_support_panel.dart';

void main() {
  testWidgets(
    'active support requires category and submits exact logical request',
    (tester) async {
      final gateway = _Gateway();
      var requestIdCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideActiveSupportPanel(
              rideId: 'ride_1',
              gateway: gateway,
              requestIdGenerator: () {
                requestIdCalls += 1;
                return 'active_support_request_1234567890';
              },
            ),
          ),
        ),
      );

      final submit = find.byKey(
        const ValueKey('ride-active-support-submit-ride_1'),
      );

      expect(
        tester.widget<FilledButton>(submit).onPressed,
        isNull,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('ride-active-support-category-ride_1'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('safety').last);
      await tester.pump();

      expect(
        tester.widget<FilledButton>(submit).onPressed,
        isNotNull,
      );

      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(requestIdCalls, 1);
      expect(gateway.calls, [
        const _Call(
          rideId: 'ride_1',
          category: 'safety',
          requestId: 'active_support_request_1234567890',
        ),
      ]);
      expect(
        find.byKey(
          const ValueKey('ride-active-support-success-ride_1'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'failed retry preserves same logical request id',
    (tester) async {
      final gateway = _Gateway()..failuresRemaining = 1;
      var requestIdCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideActiveSupportPanel(
              rideId: 'ride_2',
              gateway: gateway,
              requestIdGenerator: () {
                requestIdCalls += 1;
                return 'active_support_retry_1234567890';
              },
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(
          const ValueKey('ride-active-support-category-ride_2'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('route').last);
      await tester.pump();

      final submit = find.byKey(
        const ValueKey('ride-active-support-submit-ride_2'),
      );

      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('ride-active-support-error-ride_2'),
        ),
        findsOneWidget,
      );

      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(requestIdCalls, 1);
      expect(gateway.calls, [
        const _Call(
          rideId: 'ride_2',
          category: 'route',
          requestId: 'active_support_retry_1234567890',
        ),
        const _Call(
          rideId: 'ride_2',
          category: 'route',
          requestId: 'active_support_retry_1234567890',
        ),
      ]);
    },
  );

  testWidgets(
    'double submit is blocked while request is in flight',
    (tester) async {
      final gateway = _PendingGateway();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideActiveSupportPanel(
              rideId: 'ride_3',
              gateway: gateway,
              requestIdGenerator: () =>
                  'active_support_pending_1234567890',
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(
          const ValueKey('ride-active-support-category-ride_3'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('technical').last);
      await tester.pump();

      final submit = find.byKey(
        const ValueKey('ride-active-support-submit-ride_3'),
      );

      await tester.tap(submit);
      await tester.pump();

      expect(gateway.calls, 1);
      expect(
        tester.widget<FilledButton>(submit).onPressed,
        isNull,
      );

      gateway.complete();
      await tester.pumpAndSettle();

      expect(gateway.calls, 1);
      expect(
        find.byKey(
          const ValueKey('ride-active-support-success-ride_3'),
        ),
        findsOneWidget,
      );
    },
  );
}

class _Call {
  const _Call({
    required this.rideId,
    required this.category,
    required this.requestId,
  });

  final String rideId;
  final String category;
  final String requestId;

  @override
  bool operator ==(Object other) =>
      other is _Call &&
      other.rideId == rideId &&
      other.category == category &&
      other.requestId == requestId;

  @override
  int get hashCode =>
      Object.hash(rideId, category, requestId);
}

class _Gateway implements RideActiveSupportGateway {
  final calls = <_Call>[];
  int failuresRemaining = 0;

  @override
  Future<RideSupportCaseResult> createActiveCase({
    required String rideId,
    required String category,
    required String requestId,
  }) async {
    calls.add(
      _Call(
        rideId: rideId,
        category: category,
        requestId: requestId,
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
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        1,
        isUtc: true,
      ),
    );
  }
}

class _PendingGateway implements RideActiveSupportGateway {
  final _completer =
      Completer<RideSupportCaseResult>();
  int calls = 0;

  @override
  Future<RideSupportCaseResult> createActiveCase({
    required String rideId,
    required String category,
    required String requestId,
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
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          1,
          isUtc: true,
        ),
      ),
    );
  }
}
