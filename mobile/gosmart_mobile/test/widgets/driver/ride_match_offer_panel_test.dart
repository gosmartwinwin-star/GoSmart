import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/ride/ride_match_offer_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_ride_match_offer_controller.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/domain/ride/ride_match_offer.dart';
import 'package:gosmart_mobile/widgets/driver/ride_match_offer_panel.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 16);

  testWidgets('loading then empty state stays explicit and refreshable', (
    tester,
  ) async {
    final gateway = _Gateway();
    final pending = Completer<List<RideMatchOffer>>();

    gateway.loadCompleter = pending;

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
    );

    addTearDown(controller.dispose);

    var refreshCalls = 0;

    await _pumpPanel(
      tester,
      controller,
      onRefresh: () async {
        refreshCalls++;
      },
    );

    final loading = controller.load();

    await tester.pump();

    expect(
      find.byKey(const ValueKey('ride-match-offer-loading')),
      findsOneWidget,
    );

    pending.complete(<RideMatchOffer>[]);

    await loading;
    await tester.pump();

    expect(controller.hasLoaded, isTrue);

    expect(
      find.text(
        'Şu anda dönüş rotanıza '
        'uygun yolculuk yok.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('ride-match-offer-refresh')));

    await tester.pump();

    expect(refreshCalls, 1);
  });

  testWidgets('public offer renders only route labels and delegates accept', (
    tester,
  ) async {
    final offer = _offer(expiresAt: now.add(const Duration(minutes: 2)));

    final gateway = _Gateway()..loaded = [offer];

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
    );

    addTearDown(controller.dispose);

    await controller.load();

    RideMatchOffer? accepted;

    await _pumpPanel(
      tester,
      controller,
      onAccept: (value) async {
        accepted = value;
      },
    );

    expect(find.text('Alış: Kadıköy'), findsOneWidget);

    expect(find.text('Varış: Bostancı'), findsOneWidget);

    for (final forbidden in [
      'driver-secret',
      'passenger-secret',
      'route-secret',
      'policyVersion',
      'measurement',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }

    await tester.tap(
      find.byKey(
        const ValueKey(
          'ride-match-offer-accept-'
          'ride_public',
        ),
      ),
    );

    await tester.pump();

    expect(accepted, same(offer));
  });

  testWidgets('unknown controller failure never exposes raw exception text', (
    tester,
  ) async {
    final gateway = _Gateway()
      ..loadError = StateError('raw-secret-backend-detail');

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
    );

    addTearDown(controller.dispose);

    await controller.load();

    await _pumpPanel(tester, controller);

    expect(
      find.text(
        'Yolculuk teklifleri '
        'yüklenemedi. Tekrar deneyin.',
      ),
      findsOneWidget,
    );

    expect(find.textContaining('raw-secret'), findsNothing);

    expect(find.textContaining('StateError'), findsNothing);

    expect(
      find.byKey(const ValueKey('ride-match-offer-refresh')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  DriverRideMatchOfferController controller, {
  Future<void> Function(RideMatchOffer)? onAccept,
  Future<void> Function()? onRefresh,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RideMatchOfferPanel(
          controller: controller,
          onAccept: onAccept ?? (_) async {},
          onRefresh: onRefresh ?? () async {},
        ),
      ),
    ),
  );
}

RideMatchOffer _offer({required DateTime expiresAt}) => RideMatchOffer(
  rideId: 'ride_public',
  rideVersion: 1,
  pickup: const RideLocation(
    latitude: 40.9917,
    longitude: 29.0277,
    addressLabel: 'Kadıköy',
  ),
  dropoff: const RideLocation(
    latitude: 40.9562,
    longitude: 29.0949,
    addressLabel: 'Bostancı',
  ),
  expiresAt: expiresAt,
);

class _Gateway implements RideMatchOfferGateway {
  List<RideMatchOffer> loaded = <RideMatchOffer>[];

  Object? loadError;

  Completer<List<RideMatchOffer>>? loadCompleter;

  @override
  Future<List<RideMatchOffer>> getMyRideMatchOffers() async {
    if (loadError case final error?) {
      throw error;
    }

    if (loadCompleter case final pending?) {
      return pending.future;
    }

    return loaded;
  }

  @override
  Future<void> acceptRideMatchOffer({
    required RideMatchOffer offer,
    required String requestId,
  }) async {}
}
