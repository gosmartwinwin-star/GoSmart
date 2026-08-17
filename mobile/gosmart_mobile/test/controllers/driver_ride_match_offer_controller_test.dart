import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/ride/ride_match_offer_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_ride_match_offer_controller.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';
import 'package:gosmart_mobile/domain/ride/ride_match_offer.dart';
import 'package:gosmart_mobile/services/ride_match_offer_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 16);

  test('load keeps only unexpired public offers', () async {
    final gateway = _Gateway()
      ..loaded = [
        _offer(
          rideId: 'expired',
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ),
        _offer(rideId: 'live', expiresAt: now.add(const Duration(minutes: 1))),
      ];

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
    );

    addTearDown(controller.dispose);

    await controller.load();

    expect(gateway.loadCalls, 1);
    expect(controller.loading, isFalse);
    expect(controller.offers.map((offer) => offer.rideId), ['live']);
    expect(controller.errorMessage, isNull);
  });

  test('duplicate load while pending is ignored', () async {
    final gateway = _Gateway();
    final pending = Completer<List<RideMatchOffer>>();

    gateway.loadCompleter = pending;

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
    );

    addTearDown(controller.dispose);

    final first = controller.load();

    await Future<void>.delayed(Duration.zero);

    final second = controller.load();

    expect(gateway.loadCalls, 1);

    pending.complete(<RideMatchOffer>[]);

    await Future.wait([first, second]);

    expect(controller.loading, isFalse);
  });

  test('transient accept retry reuses same request id', () async {
    final offer = _offer(
      rideId: 'ride_retry',
      expiresAt: now.add(const Duration(minutes: 2)),
    );

    final gateway = _Gateway()
      ..loaded = [offer]
      ..acceptFailures.add(const RideMatchOfferException('unavailable'));

    var generated = 0;

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
      requestIdGenerator: () {
        generated++;
        return 'request_123456789';
      },
    );

    addTearDown(controller.dispose);

    await controller.load();

    expect(await controller.accept(offer), isFalse);

    expect(controller.offers, hasLength(1));

    expect(
      controller.errorMessage,
      'Yolculuk kabulü doğrulanamadı. Tekrar deneyin.',
    );

    expect(await controller.accept(offer), isTrue);

    expect(generated, 1);
    expect(gateway.acceptCalls, 2);

    expect(gateway.requestIds, ['request_123456789', 'request_123456789']);

    expect(controller.offers, isEmpty);

    expect(controller.acceptedRideId, 'ride_retry');
  });

  test('expired offer is rejected before gateway', () async {
    final offer = _offer(
      rideId: 'ride_expired',
      expiresAt: now.add(const Duration(seconds: 1)),
    );

    final gateway = _Gateway()..loaded = [offer];

    var current = now;

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => current,
      requestIdGenerator: () => 'request_123456789',
    );

    addTearDown(controller.dispose);

    await controller.load();

    current = now.add(const Duration(seconds: 2));

    expect(await controller.accept(offer), isFalse);

    expect(gateway.acceptCalls, 0);
    expect(controller.offers, isEmpty);

    expect(controller.errorMessage, 'Bu yolculuk teklifinin süresi doldu.');
  });

  test('stale server rejection removes only rejected offer', () async {
    final stale = _offer(
      rideId: 'stale',
      expiresAt: now.add(const Duration(minutes: 2)),
    );

    final other = _offer(
      rideId: 'other',
      expiresAt: now.add(const Duration(minutes: 2)),
    );

    final gateway = _Gateway()
      ..loaded = [stale, other]
      ..acceptFailures.add(
        const RideMatchOfferException(
          'failed-precondition',
          reason: 'ride_match_offer_stale',
        ),
      );

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
      requestIdGenerator: () => 'request_123456789',
    );

    addTearDown(controller.dispose);

    await controller.load();

    expect(await controller.accept(stale), isFalse);

    expect(controller.offers.map((offer) => offer.rideId), ['other']);

    expect(controller.errorMessage, 'Bu yolculuk teklifi artık geçerli değil.');
  });

  test('driver-wide precondition clears all offers', () async {
    final first = _offer(
      rideId: 'first',
      expiresAt: now.add(const Duration(minutes: 2)),
    );

    final second = _offer(
      rideId: 'second',
      expiresAt: now.add(const Duration(minutes: 2)),
    );

    final gateway = _Gateway()
      ..loaded = [first, second]
      ..acceptFailures.add(
        const RideMatchOfferException(
          'failed-precondition',
          reason: 'driver_active_ride_exists',
        ),
      );

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
      requestIdGenerator: () => 'request_123456789',
    );

    addTearDown(controller.dispose);

    await controller.load();

    expect(await controller.accept(first), isFalse);

    expect(controller.offers, isEmpty);

    expect(controller.errorMessage, 'Zaten aktif bir yolculuğunuz var.');
  });

  test('unknown failures never surface raw backend detail', () async {
    final gateway = _Gateway()..loadError = StateError('secret backend detail');

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
    );

    addTearDown(controller.dispose);

    await controller.load();

    expect(
      controller.errorMessage,
      'Yolculuk teklifleri yüklenemedi. Tekrar deneyin.',
    );

    expect(controller.errorMessage, isNot(contains('secret')));

    expect(controller.errorMessage, isNot(contains('StateError')));
  });

  test('accepted marker can be consumed locally', () async {
    final offer = _offer(
      rideId: 'accepted',
      expiresAt: now.add(const Duration(minutes: 2)),
    );

    final gateway = _Gateway()..loaded = [offer];

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => now,
      requestIdGenerator: () => 'request_123456789',
    );

    addTearDown(controller.dispose);

    await controller.load();

    expect(await controller.accept(offer), isTrue);

    expect(controller.acceptedRideId, 'accepted');

    controller.clearAcceptedRide();

    expect(controller.acceptedRideId, isNull);
  });
}

RideMatchOffer _offer({
  required String rideId,
  required DateTime expiresAt,
  int rideVersion = 1,
}) => RideMatchOffer(
  rideId: rideId,
  rideVersion: rideVersion,
  pickup: const RideLocation(
    latitude: 41.0082,
    longitude: 28.9784,
    addressLabel: 'Pickup',
  ),
  dropoff: const RideLocation(
    latitude: 41.0151,
    longitude: 28.9795,
    addressLabel: 'Dropoff',
  ),
  expiresAt: expiresAt,
);

class _Gateway implements RideMatchOfferGateway {
  List<RideMatchOffer> loaded = <RideMatchOffer>[];

  Object? loadError;

  Completer<List<RideMatchOffer>>? loadCompleter;

  final List<Object> acceptFailures = <Object>[];

  final List<String> requestIds = <String>[];

  int loadCalls = 0;
  int acceptCalls = 0;

  @override
  Future<List<RideMatchOffer>> getMyRideMatchOffers() async {
    loadCalls++;

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
  }) async {
    acceptCalls++;
    requestIds.add(requestId);

    if (acceptFailures.isNotEmpty) {
      throw acceptFailures.removeAt(0);
    }
  }
}
