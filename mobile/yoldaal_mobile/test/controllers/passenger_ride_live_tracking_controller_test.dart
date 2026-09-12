import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_live_tracking_gateway.dart';
import 'package:yoldaal_mobile/controllers/passenger_ride_live_tracking_controller.dart';
import 'package:yoldaal_mobile/domain/return_route/geo_coordinate.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';

void main() {
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('active status performs immediate first read', () async {
    final ride = _RideState();
    final gateway = _Gateway();
    final timers = _PeriodicTimerFactory();

    gateway.handler = (_) async => _freshSnapshot(
      etaSeconds: 180,
    );

    final controller = PassengerRideLiveTrackingController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      gateway: gateway,
      periodicTimerFactory: timers.create,
    )..start();

    expect(gateway.calls, 0);
    expect(controller.isActive, isFalse);

    ride.set(
      rideId: 'ride_1',
      status: RideStatus.driverEnRoute,
    );

    await settle();

    expect(gateway.calls, 1);
    expect(controller.isActive, isTrue);
    expect(controller.isUpdating, isFalse);
    expect(controller.driverLocation?.latitude, 41.0082);
    expect(controller.etaSeconds, 180);
    expect(
      timers.activeDuration,
      passengerRideLiveTrackingPollInterval,
    );

    controller.dispose();
  });

  test('five second polling never overlaps an in-flight read', () async {
    final ride = _RideState(
      rideId: 'ride_1',
      status: RideStatus.driverEnRoute,
    );

    final firstRead =
        Completer<RideLiveTrackingSnapshot>();

    final gateway = _Gateway();
    final timers = _PeriodicTimerFactory();

    gateway.handler = (_) {
      if (gateway.calls == 1) {
        return firstRead.future;
      }

      return Future<RideLiveTrackingSnapshot>.value(
        _freshSnapshot(
          etaSeconds: 120,
        ),
      );
    };

    final controller = PassengerRideLiveTrackingController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      gateway: gateway,
      periodicTimerFactory: timers.create,
    )..start();

    await settle();

    expect(gateway.calls, 1);

    timers.fire();
    await settle();

    expect(
      gateway.calls,
      1,
      reason: 'Periodic tick must skip while read is in flight.',
    );

    firstRead.complete(
      _freshSnapshot(
        etaSeconds: 180,
      ),
    );

    await settle();

    expect(gateway.calls, 1);

    timers.fire();
    await settle();

    expect(gateway.calls, 2);

    controller.dispose();
  });

  test('active status change queues one immediate read without overlap', () async {
    final ride = _RideState(
      rideId: 'ride_1',
      status: RideStatus.driverEnRoute,
    );

    final firstRead =
        Completer<RideLiveTrackingSnapshot>();

    final gateway = _Gateway();
    final timers = _PeriodicTimerFactory();

    gateway.handler = (_) {
      if (gateway.calls == 1) {
        return firstRead.future;
      }

      return Future<RideLiveTrackingSnapshot>.value(
        RideLiveTrackingSnapshot(
          driverLocation: GeoCoordinate(
            latitude: 41.01,
            longitude: 29.01,
          ),
          updatedAtMillis: 3000,
          etaSeconds: null,
          etaUpdatedAtMillis: null,
        ),
      );
    };

    final controller = PassengerRideLiveTrackingController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      gateway: gateway,
      periodicTimerFactory: timers.create,
    )..start();

    await settle();
    expect(gateway.calls, 1);

    ride.set(
      rideId: 'ride_1',
      status: RideStatus.driverArrived,
    );

    await settle();

    expect(
      gateway.calls,
      1,
      reason: 'Status transition must not overlap the old callable.',
    );
    expect(controller.isUpdating, isTrue);
    expect(controller.driverLocation, isNull);

    firstRead.complete(
      _freshSnapshot(
        etaSeconds: 180,
      ),
    );

    await settle();

    expect(gateway.calls, 2);
    expect(controller.isUpdating, isFalse);
    expect(controller.driverLocation?.latitude, 41.01);
    expect(
      controller.etaSeconds,
      isNull,
      reason: 'driverArrived ETA must stay hidden.',
    );

    controller.dispose();
  });

  test('failure clears previously authoritative marker and ETA', () async {
    final ride = _RideState(
      rideId: 'ride_1',
      status: RideStatus.inProgress,
    );

    final gateway = _Gateway();
    final timers = _PeriodicTimerFactory();

    gateway.handler = (_) async {
      if (gateway.calls == 1) {
        return _freshSnapshot(
          etaSeconds: 240,
        );
      }

      throw const RideLiveTrackingException(
        code: 'unavailable',
      );
    };

    final controller = PassengerRideLiveTrackingController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      gateway: gateway,
      periodicTimerFactory: timers.create,
    )..start();

    await settle();

    expect(controller.driverLocation, isNotNull);
    expect(controller.etaSeconds, 240);
    expect(controller.isUpdating, isFalse);

    timers.fire();
    await settle();

    expect(controller.driverLocation, isNull);
    expect(controller.etaSeconds, isNull);
    expect(controller.isUpdating, isTrue);

    controller.dispose();
  });

  test('server null location clears marker and ETA into updating state', () async {
    final ride = _RideState(
      rideId: 'ride_1',
      status: RideStatus.driverEnRoute,
    );

    final gateway = _Gateway();
    final timers = _PeriodicTimerFactory();

    gateway.handler = (_) async {
      if (gateway.calls == 1) {
        return _freshSnapshot(
          etaSeconds: 180,
        );
      }

      return const RideLiveTrackingSnapshot(
        driverLocation: null,
        updatedAtMillis: 5000,
        etaSeconds: null,
        etaUpdatedAtMillis: null,
      );
    };

    final controller = PassengerRideLiveTrackingController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      gateway: gateway,
      periodicTimerFactory: timers.create,
    )..start();

    await settle();

    expect(controller.driverLocation, isNotNull);

    timers.fire();
    await settle();

    expect(controller.driverLocation, isNull);
    expect(controller.etaSeconds, isNull);
    expect(controller.isUpdating, isTrue);

    controller.dispose();
  });

  test('terminal and null ride stop polling immediately', () async {
    final ride = _RideState(
      rideId: 'ride_1',
      status: RideStatus.inProgress,
    );

    final gateway = _Gateway();
    final timers = _PeriodicTimerFactory();

    gateway.handler = (_) async => _freshSnapshot(
      etaSeconds: 120,
    );

    final controller = PassengerRideLiveTrackingController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      gateway: gateway,
      periodicTimerFactory: timers.create,
    )..start();

    await settle();

    expect(controller.isActive, isTrue);
    expect(timers.isActive, isTrue);

    ride.set(
      rideId: 'ride_1',
      status: RideStatus.completed,
    );

    await settle();

    expect(controller.isActive, isFalse);
    expect(controller.driverLocation, isNull);
    expect(controller.etaSeconds, isNull);
    expect(timers.isActive, isFalse);

    final callsAtTerminal = gateway.calls;

    timers.fire();
    await settle();

    expect(gateway.calls, callsAtTerminal);

    ride.set(
      rideId: null,
      status: null,
    );

    await settle();

    expect(controller.isActive, isFalse);

    controller.dispose();
  });
}

RideLiveTrackingSnapshot _freshSnapshot({
  required int etaSeconds,
}) =>
    RideLiveTrackingSnapshot(
      driverLocation: GeoCoordinate(
        latitude: 41.0082,
        longitude: 28.9784,
      ),
      updatedAtMillis: 2000,
      etaSeconds: etaSeconds,
      etaUpdatedAtMillis: 1900,
    );

class _RideState extends ChangeNotifier {
  _RideState({
    this.rideId,
    this.status,
  });

  String? rideId;
  RideStatus? status;

  void set({
    required String? rideId,
    required RideStatus? status,
  }) {
    this.rideId = rideId;
    this.status = status;
    notifyListeners();
  }
}

class _Gateway implements RideLiveTrackingGateway {
  int calls = 0;

  Future<RideLiveTrackingSnapshot> Function(
    String rideId,
  )? handler;

  @override
  Future<RideLiveTrackingSnapshot> getTracking({
    required String rideId,
  }) {
    calls += 1;

    final currentHandler = handler;

    if (currentHandler == null) {
      throw StateError('No tracking handler configured.');
    }

    return currentHandler(rideId);
  }
}

class _PeriodicTimerFactory {
  _ManualPeriodicTimer? _timer;

  Timer create(
    Duration duration,
    void Function(Timer timer) callback,
  ) {
    final timer = _ManualPeriodicTimer(
      duration: duration,
      callback: callback,
    );

    _timer?.cancel();
    _timer = timer;

    return timer;
  }

  Duration? get activeDuration =>
      _timer?.isActive == true
          ? _timer?.duration
          : null;

  bool get isActive =>
      _timer?.isActive ?? false;

  void fire() {
    _timer?.fire();
  }
}

class _ManualPeriodicTimer implements Timer {
  _ManualPeriodicTimer({
    required this.duration,
    required this.callback,
  });

  final Duration duration;
  final void Function(Timer timer) callback;

  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) {
      return;
    }

    _tick += 1;
    callback(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }
}
