import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_history_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_rating_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_support_gateway.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/domain/ride/ride_history.dart';
import 'package:yoldaal_mobile/screens/ride/ride_history_screen.dart';

void main() {
  testWidgets('passenger history listelenir ve driver scope secilebilir', (
    tester,
  ) async {
    final gateway = _Gateway();

    await tester.pumpWidget(
      MaterialApp(home: RideHistoryScreen(gateway: gateway)),
    );

    await tester.pumpAndSettle();

    expect(find.text('Tamamland\u0131'), findsOneWidget);

    expect(find.text('Passenger Pickup'), findsOneWidget);

    expect(gateway.scopes, [RideHistoryScope.passenger]);

    await tester.tap(find.byKey(const ValueKey('ride-history-driver-scope')));

    await tester.pumpAndSettle();

    expect(gateway.scopes, [
      RideHistoryScope.passenger,
      RideHistoryScope.driver,
    ]);

    expect(find.text('Driver Pickup'), findsOneWidget);
  });

  testWidgets('pagination cursor ile daha fazla yukler', (tester) async {
    final gateway = _PagingGateway();

    await tester.pumpWidget(
      MaterialApp(home: RideHistoryScreen(gateway: gateway)),
    );

    await tester.pumpAndSettle();

    expect(find.text('First Pickup'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('ride-history-load-more')),
      findsOneWidget,
    );

    final loadMore = find.byKey(
      const ValueKey('ride-history-load-more'),
    );

    await tester.ensureVisible(loadMore);
    await tester.pumpAndSettle();

    await tester.tap(loadMore);

    await tester.pumpAndSettle();

    expect(find.text('First Pickup'), findsOneWidget);

    expect(find.text('Second Pickup'), findsOneWidget);

    expect(gateway.cursors, [
      null,
      const RideHistoryCursor(updatedAtMillis: 2000, rideId: 'first'),
    ]);
  });

  testWidgets('raw gateway error UI metnine sizmaz', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: RideHistoryScreen(gateway: _FailingGateway())),
    );

    await tester.pumpAndSettle();

    expect(
      find.textContaining('Yolculuk ge\u00e7mi\u015fi y\u00fcklenemedi'),
      findsOneWidget,
    );

    expect(find.textContaining('secret-detail'), findsNothing);
  });
  testWidgets('completed ride own rating status ve submit akisini gosterir', (
    tester,
  ) async {
    final history = _Gateway();
    final ratings = _RatingGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: history,
          ratingGateway: ratings,
          requestIdGenerator:
              () => 'rating_request_1234567890',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(ratings.statusRideIds, ['passenger']);
    expect(
      find.text('Bu yolculuğu puanlayın'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('ride-rating-passenger-star-5'),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-rating-submit-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    expect(ratings.submitRatings, [5]);
    expect(
      ratings.submitRequestIds,
      ['rating_request_1234567890'],
    );
    expect(find.text('Puanınız: 5/5'), findsOneWidget);
    expect(
      find.text('Bu yolculuğu puanlayın'),
      findsNothing,
    );
  });

  testWidgets('driver scope da ayni completed rating yuzeyini kullanir', (
    tester,
  ) async {
    final history = _Gateway();
    final ratings = _RatingGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: history,
          ratingGateway: ratings,
          requestIdGenerator:
              () => 'rating_request_1234567890',
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-history-driver-scope'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      ratings.statusRideIds,
      containsAllInOrder(['passenger', 'driver']),
    );
    expect(
      find.byKey(
        const ValueKey('ride-rating-panel-driver'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('daha once verilen own score tekrar puanlama aksiyonu gostermez', (
    tester,
  ) async {
    final ratings = _RatingGateway()
      ..status = RideRatingStatus(
        rideId: 'passenger',
        hasSubmitted: true,
        rating: 4,
        submittedAt:
            DateTime.fromMillisecondsSinceEpoch(
              123456,
              isUtc: true,
            ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _Gateway(),
          ratingGateway: ratings,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Puanınız: 4/5'), findsOneWidget);
    expect(
      find.text('Bu yolculuğu puanlayın'),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('ride-rating-submit-passenger'),
      ),
      findsNothing,
    );
  });

  testWidgets('rating status hatasi fail-soft ve raw reason sizdirmaz', (
    tester,
  ) async {
    final ratings = _RatingGateway()
      ..statusError = const RideGatewayException(
        'internal',
        reason: 'secret-rating-detail',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _Gateway(),
          ratingGateway: ratings,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text(
        'Puan durumu alınamadı. Lütfen tekrar deneyin.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'ride-rating-status-retry-passenger',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('secret-rating-detail'),
      findsNothing,
    );
    expect(
      find.text('Bu yolculuğu puanlayın'),
      findsNothing,
    );
  });

  testWidgets('ayni logical rating retry ayni requestId kullanir', (
    tester,
  ) async {
    var generated = 0;

    final ratings = _RatingGateway()
      ..submitFailuresRemaining = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _Gateway(),
          ratingGateway: ratings,
          requestIdGenerator: () =>
              'rating_retry_${++generated}_1234567890',
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-rating-passenger-star-3'),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-rating-submit-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Puan gönderilemedi. Lütfen tekrar deneyin.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('ride-rating-submit-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    expect(ratings.submitRatings, [3, 3]);
    expect(ratings.submitRequestIds.length, 2);
    expect(
      ratings.submitRequestIds[0],
      ratings.submitRequestIds[1],
    );
    expect(generated, 1);
    expect(find.text('Puanınız: 3/5'), findsOneWidget);
  });

  testWidgets('cancelled terminal ride rating callable cagirmiyor', (
    tester,
  ) async {
    final ratings = _RatingGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _CancelledGateway(),
          ratingGateway: ratings,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(ratings.statusRideIds, isEmpty);
    expect(
      find.text('Bu yolculuğu puanlayın'),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('ride-rating-panel-cancelled'),
      ),
      findsNothing,
    );
  });

  testWidgets('completed terminal ride support category ve submit akisini kullanir', (
    tester,
  ) async {
    final support = _SupportGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _Gateway(),
          ratingGateway: _RatingGateway(),
          supportGateway: support,
          requestIdGenerator:
              () => 'support_request_1234567890',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('ride-support-panel-passenger'),
      ),
      findsOneWidget,
    );

    final submit = find.byKey(
      const ValueKey('ride-support-submit-passenger'),
    );

    expect(
      tester.widget<FilledButton>(submit).onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('ride-support-category-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Güvenlik').last);
    await tester.pump();

    expect(
      tester.widget<FilledButton>(submit).onPressed,
      isNotNull,
    );

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(support.rideIds, ['passenger']);
    expect(support.categories, ['safety']);
    expect(
      support.requestIds,
      ['support_request_1234567890'],
    );
    expect(
      find.text('Destek talebiniz alındı.'),
      findsOneWidget,
    );
  });

  testWidgets('support logical retry ayni requestId kullanir', (
    tester,
  ) async {
    var generated = 0;

    final support = _SupportGateway()
      ..failuresRemaining = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _Gateway(),
          ratingGateway: _RatingGateway(),
          supportGateway: support,
          requestIdGenerator: () =>
              'support_retry_${++generated}_1234567890',
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-support-category-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rota').last);
    await tester.pump();

    final submit = find.byKey(
      const ValueKey('ride-support-submit-passenger'),
    );

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Destek talebi gönderilemedi. Lütfen tekrar deneyin.',
      ),
      findsOneWidget,
    );

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(generated, 1);
    expect(support.categories, ['route', 'route']);
    expect(
      support.requestIds,
      [
        'support_retry_1_1234567890',
        'support_retry_1_1234567890',
      ],
    );
    expect(
      find.text('Destek talebiniz alındı.'),
      findsOneWidget,
    );
  });

  testWidgets('failed support category change yeni logical requestId uretir', (
    tester,
  ) async {
    var generated = 0;

    final support = _SupportGateway()
      ..failuresRemaining = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _Gateway(),
          ratingGateway: _RatingGateway(),
          supportGateway: support,
          requestIdGenerator: () =>
              'support_change_${++generated}_1234567890',
        ),
      ),
    );

    await tester.pumpAndSettle();

    final category = find.byKey(
      const ValueKey('ride-support-category-passenger'),
    );

    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rota').last);
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-support-submit-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ücret').last);
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-support-submit-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    expect(generated, 2);
    expect(support.categories, ['route', 'fare']);
    expect(
      support.requestIds,
      [
        'support_change_1_1234567890',
        'support_change_2_1234567890',
      ],
    );
  });

  testWidgets('support backend raw reason UI metnine sizmaz', (
    tester,
  ) async {
    final support = _SupportGateway()
      ..error = const RideGatewayException(
        'failed-precondition',
        reason: 'secret-support-detail',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _Gateway(),
          ratingGateway: _RatingGateway(),
          supportGateway: support,
          requestIdGenerator:
              () => 'support_request_1234567890',
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-support-category-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Davranış').last);
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-support-submit-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Destek talebi gönderilemedi. Lütfen tekrar deneyin.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('secret-support-detail'),
      findsNothing,
    );
  });

  testWidgets('cancelled ve expired terminal rides support yuzeyi gosterir', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _TerminalSupportGateway(),
          supportGateway: _SupportGateway(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('ride-support-panel-cancelled'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('ride-support-panel-expired'),
      ),
      findsOneWidget,
    );

    expect(
      find.byKey(
        const ValueKey('ride-rating-panel-cancelled'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('ride-rating-panel-expired'),
      ),
      findsNothing,
    );
  });

  testWidgets('driver scope shared support yuzeyini kullanir', (
    tester,
  ) async {
    final support = _SupportGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _Gateway(),
          ratingGateway: _RatingGateway(),
          supportGateway: support,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('ride-support-panel-passenger'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('ride-history-driver-scope'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('ride-support-panel-driver'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('support submit while pending ikinci gateway call olusturmaz', (
    tester,
  ) async {
    final pending = Completer<RideSupportCaseResult>();

    final support = _SupportGateway()
      ..pendingResult = pending;

    await tester.pumpWidget(
      MaterialApp(
        home: RideHistoryScreen(
          gateway: _Gateway(),
          ratingGateway: _RatingGateway(),
          supportGateway: support,
          requestIdGenerator:
              () => 'support_pending_1234567890',
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('ride-support-category-passenger'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Güvenlik').last);
    await tester.pump();

    final submit = find.byKey(
      const ValueKey('ride-support-submit-passenger'),
    );

    expect(
      tester.widget<FilledButton>(submit).onPressed,
      isNotNull,
    );

    await tester.tap(submit);
    await tester.pump();

    expect(support.rideIds, ['passenger']);
    expect(support.categories, ['safety']);
    expect(
      support.requestIds,
      ['support_pending_1234567890'],
    );

    expect(
      tester.widget<FilledButton>(submit).onPressed,
      isNull,
    );

    await tester.tap(submit);
    await tester.pump();

    expect(
      support.rideIds,
      ['passenger'],
      reason:
          'A second tap while the first support request is pending '
          'must not create another gateway call.',
    );

    pending.complete(
      RideSupportCaseResult(
        rideId: 'passenger',
        caseId: 'support-case-pending',
        category: 'safety',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          456789,
          isUtc: true,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Destek talebiniz alındı.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(submit).onPressed,
      isNull,
    );
    expect(support.rideIds, ['passenger']);
  });
}

CanonicalRide _ride(
  String id,
  String pickup, {
  RideStatus status = RideStatus.completed,
}) => CanonicalRide(
  rideId: id,
  status: status,
  version: 5,
  driverId: 'driver-1',
  pickup: RideLocation(latitude: 41, longitude: 29, addressLabel: pickup),
  dropoff: const RideLocation(
    latitude: 41.1,
    longitude: 29.1,
    addressLabel: 'Dropoff',
  ),
  route: const RideRoute(
    distanceMeters: 1500,
    durationSeconds: 420,
    encodedPolyline: 'encoded',
  ),
  completedAt: status == RideStatus.completed
      ? DateTime.fromMillisecondsSinceEpoch(
          2000,
          isUtc: true,
        )
      : null,
  cancelledAt: status == RideStatus.cancelled
      ? DateTime.fromMillisecondsSinceEpoch(
          2000,
          isUtc: true,
        )
      : null,
  expiredAt: status == RideStatus.expired
      ? DateTime.fromMillisecondsSinceEpoch(
          2000,
          isUtc: true,
        )
      : null,
);

class _Gateway implements RideHistoryGateway {
  final scopes = <RideHistoryScope>[];

  @override
  Future<RideHistoryPage> loadPage({
    required RideHistoryScope scope,
    int pageSize = 20,
    RideHistoryCursor? cursor,
  }) async {
    scopes.add(scope);

    return RideHistoryPage(
      rides: [
        _ride(
          scope.name,
          scope == RideHistoryScope.passenger
              ? 'Passenger Pickup'
              : 'Driver Pickup',
        ),
      ],
      nextCursor: null,
    );
  }
}

class _PagingGateway implements RideHistoryGateway {
  final cursors = <RideHistoryCursor?>[];

  @override
  Future<RideHistoryPage> loadPage({
    required RideHistoryScope scope,
    int pageSize = 20,
    RideHistoryCursor? cursor,
  }) async {
    cursors.add(cursor);

    if (cursor == null) {
      return RideHistoryPage(
        rides: [_ride('first', 'First Pickup')],
        nextCursor: const RideHistoryCursor(
          updatedAtMillis: 2000,
          rideId: 'first',
        ),
      );
    }

    return RideHistoryPage(
      rides: [_ride('second', 'Second Pickup')],
      nextCursor: null,
    );
  }
}

class _FailingGateway implements RideHistoryGateway {
  @override
  Future<RideHistoryPage> loadPage({
    required RideHistoryScope scope,
    int pageSize = 20,
    RideHistoryCursor? cursor,
  }) async {
    throw const RideGatewayException('internal', reason: 'secret-detail');
  }
}
class _RatingGateway implements RideRatingGateway {
  RideRatingStatus? status;
  RideGatewayException? statusError;
  int submitFailuresRemaining = 0;

  final statusRideIds = <String>[];
  final submitRideIds = <String>[];
  final submitRatings = <int>[];
  final submitRequestIds = <String>[];

  @override
  Future<RideRatingStatus> getMyRatingStatus({
    required String rideId,
  }) async {
    statusRideIds.add(rideId);

    if (statusError case final error?) {
      throw error;
    }

    final configured = status;

    if (configured != null) {
      return RideRatingStatus(
        rideId: rideId,
        hasSubmitted: configured.hasSubmitted,
        rating: configured.rating,
        submittedAt: configured.submittedAt,
      );
    }

    return RideRatingStatus(
      rideId: rideId,
      hasSubmitted: false,
    );
  }

  @override
  Future<RideRatingStatus> submitRating({
    required String rideId,
    required int rating,
    required String requestId,
  }) async {
    submitRideIds.add(rideId);
    submitRatings.add(rating);
    submitRequestIds.add(requestId);

    if (submitFailuresRemaining > 0) {
      submitFailuresRemaining -= 1;
      throw const RideGatewayException('unavailable');
    }

    return RideRatingStatus(
      rideId: rideId,
      hasSubmitted: true,
      rating: rating,
      submittedAt:
          DateTime.fromMillisecondsSinceEpoch(
            456789,
            isUtc: true,
          ),
    );
  }
}

class _SupportGateway implements RideSupportGateway {
  final rideIds = <String>[];
  final categories = <String>[];
  final requestIds = <String>[];

  RideGatewayException? error;
  int failuresRemaining = 0;
  Completer<RideSupportCaseResult>? pendingResult;

  @override
  Future<RideSupportCaseResult> createCase({
    required String rideId,
    required String category,
    required String requestId,
  }) async {
    rideIds.add(rideId);
    categories.add(category);
    requestIds.add(requestId);

    if (error case final value?) {
      throw value;
    }

    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const RideGatewayException('unavailable');
    }

    final pending = pendingResult;

    if (pending != null) {
      return pending.future;
    }

    return RideSupportCaseResult(
      rideId: rideId,
      caseId: 'support-case-${requestIds.length}',
      category: category,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        456789,
        isUtc: true,
      ),
    );
  }
}

class _TerminalSupportGateway implements RideHistoryGateway {
  @override
  Future<RideHistoryPage> loadPage({
    required RideHistoryScope scope,
    int pageSize = 20,
    RideHistoryCursor? cursor,
  }) async {
    return RideHistoryPage(
      rides: [
        _ride(
          'cancelled',
          'Cancelled Pickup',
          status: RideStatus.cancelled,
        ),
        _ride(
          'expired',
          'Expired Pickup',
          status: RideStatus.expired,
        ),
      ],
      nextCursor: null,
    );
  }
}
class _CancelledGateway implements RideHistoryGateway {
  @override
  Future<RideHistoryPage> loadPage({
    required RideHistoryScope scope,
    int pageSize = 20,
    RideHistoryCursor? cursor,
  }) async {
    return RideHistoryPage(
      rides: [
        _ride(
          'cancelled',
          'Cancelled Pickup',
          status: RideStatus.cancelled,
        ),
      ],
      nextCursor: null,
    );
  }
}
