import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/application/ride/ride_history_gateway.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/domain/ride/ride_history.dart';
import 'package:gosmart_mobile/screens/ride/ride_history_screen.dart';

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

    await tester.tap(find.byKey(const ValueKey('ride-history-load-more')));

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
}

CanonicalRide _ride(String id, String pickup) => CanonicalRide(
  rideId: id,
  status: RideStatus.completed,
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
  completedAt: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
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
