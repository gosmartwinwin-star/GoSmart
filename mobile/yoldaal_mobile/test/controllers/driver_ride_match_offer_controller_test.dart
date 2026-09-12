import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_match_offer_gateway.dart';
import 'package:yoldaal_mobile/controllers/driver_ride_match_offer_controller.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/domain/ride/ride_match_offer.dart';
import 'package:yoldaal_mobile/services/ride_match_offer_service.dart';

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
  test(
    'foreground polling refreshes every 15 seconds and start is idempotent',
    () async {
      final gateway = _Gateway();
      final timerFactory = _ManualPeriodicTimerFactory();

      final controller = DriverRideMatchOfferController(
        gateway: gateway,
        now: () => now,
        periodicTimerFactory: timerFactory.create,
      );

      void listener() {}
      controller.addListener(listener);

      addTearDown(() {
        controller.removeListener(listener);
        controller.dispose();
      });

      expect(controller.startPolling(), isTrue);
      expect(controller.startPolling(), isFalse);
      expect(controller.polling, isTrue);
      expect(timerFactory.timers, hasLength(1));
      expect(timerFactory.latest.interval, driverRideMatchOfferPollInterval);
      expect(gateway.loadCalls, 0);

      gateway.loaded = [
        _offer(
          rideId: 'polled',
          expiresAt: now.add(const Duration(minutes: 2)),
        ),
      ];

      timerFactory.latest.fire();
      await Future<void>.delayed(Duration.zero);

      expect(gateway.loadCalls, 1);
      expect(controller.offers.map((offer) => offer.rideId), ['polled']);
      expect(controller.polling, isTrue);

      controller.stopPolling();

      expect(controller.polling, isFalse);
      expect(timerFactory.latest.isActive, isFalse);
    },
  );

  test(
    'countdown advances 2 to 1 minute and removes offer at exact expiry without refetch',
    () async {
      final base = DateTime.utc(2026, 8, 15, 16);
      var current = base;

      final gateway = _Gateway()
        ..loaded = [
          _offer(
            rideId: 'ride-countdown',
            expiresAt: base.add(const Duration(minutes: 2)),
          ),
        ];

      final timerFactory = _ManualCountdownTimerFactory();

      final controller = DriverRideMatchOfferController(
        gateway: gateway,
        now: () => current,
        countdownTimerFactory: timerFactory.create,
      );

      void listener() {}
      controller.addListener(listener);

      addTearDown(() {
        controller.removeListener(listener);
        controller.dispose();
      });

      await controller.load();

      expect(controller.offers, hasLength(1));
      expect(controller.remainingMinutesFor(controller.offers.single), 2);
      expect(timerFactory.timers, hasLength(1));
      expect(timerFactory.latest.delay, const Duration(minutes: 1));
      expect(gateway.loadCalls, 1);

      current = base.add(const Duration(minutes: 1));
      timerFactory.latest.fire();

      expect(controller.offers, hasLength(1));
      expect(controller.remainingMinutesFor(controller.offers.single), 1);
      expect(timerFactory.timers, hasLength(2));
      expect(timerFactory.latest.delay, const Duration(minutes: 1));
      expect(gateway.loadCalls, 1);

      current = base.add(const Duration(minutes: 2));
      timerFactory.latest.fire();

      expect(controller.offers, isEmpty);
      expect(timerFactory.timers, hasLength(2));
      expect(gateway.loadCalls, 1);
    },
  );

  test('dispose cancels active countdown and polling timers', () async {
    final base = DateTime.utc(2026, 8, 15, 16);

    final gateway = _Gateway()
      ..loaded = [
        _offer(
          rideId: 'ride-countdown-dispose',
          expiresAt: base.add(const Duration(minutes: 2)),
        ),
      ];

    final countdownTimerFactory = _ManualCountdownTimerFactory();
    final periodicTimerFactory = _ManualPeriodicTimerFactory();

    final controller = DriverRideMatchOfferController(
      gateway: gateway,
      now: () => base,
      countdownTimerFactory: countdownTimerFactory.create,
      periodicTimerFactory: periodicTimerFactory.create,
    );

    var disposed = false;
    void listener() {}

    controller.addListener(listener);

    addTearDown(() {
      if (!disposed) {
        controller.removeListener(listener);
        controller.dispose();
      }
    });

    await controller.load();
    expect(controller.startPolling(), isTrue);

    final countdownTimer = countdownTimerFactory.latest;
    final pollingTimer = periodicTimerFactory.latest;

    expect(countdownTimer.isActive, isTrue);
    expect(pollingTimer.isActive, isTrue);

    controller.removeListener(listener);
    controller.dispose();
    disposed = true;

    expect(countdownTimer.isActive, isFalse);
    expect(pollingTimer.isActive, isFalse);
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
  pickupDetourMeters: 900,
  pickupDetourSeconds: 180,
  dropoffDetourMeters: 1200,
  dropoffDetourSeconds: 240,
  passengerTripDistanceMeters: 10000,
  passengerTripDurationSeconds: 1200,
  expiresAt: expiresAt,
);

class _ManualCountdownTimerFactory {
  final List<_ManualCountdownTimer> timers = <_ManualCountdownTimer>[];

  Timer create(Duration delay, void Function() callback) {
    final timer = _ManualCountdownTimer(delay: delay, callback: callback);

    timers.add(timer);
    return timer;
  }

  _ManualCountdownTimer get latest => timers.last;
}

class _ManualCountdownTimer implements Timer {
  _ManualCountdownTimer({
    required this.delay,
    required void Function() callback,
  }) : _callback = callback;

  final Duration delay;
  final void Function() _callback;

  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) {
      return;
    }

    _active = false;
    _tick = 1;
    _callback();
  }
}

class _ManualPeriodicTimerFactory {
  final List<_ManualPeriodicTimer> timers = <_ManualPeriodicTimer>[];

  Timer create(Duration interval, void Function(Timer) callback) {
    final timer = _ManualPeriodicTimer(interval: interval, callback: callback);

    timers.add(timer);
    return timer;
  }

  _ManualPeriodicTimer get latest => timers.last;
}

class _ManualPeriodicTimer implements Timer {
  _ManualPeriodicTimer({
    required this.interval,
    required void Function(Timer) callback,
  }) : _callback = callback;

  final Duration interval;
  final void Function(Timer) _callback;

  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) {
      return;
    }

    _tick++;
    _callback(this);
  }
}

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
