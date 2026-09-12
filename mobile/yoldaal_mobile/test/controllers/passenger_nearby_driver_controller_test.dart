import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/controllers/passenger_nearby_driver_controller.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/services/nearby_passenger_driver_service.dart';

void main() {
  test('starts immediate nearby discovery only for matching ride', () async {
    final ride = _RideHarness(
      rideId: 'ride-matching',
      status: RideStatus.matching,
    );

    final timers = <_FakeTimer>[];
    var loadCalls = 0;

    final controller = PassengerNearbyDriverController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      loader: () async {
        loadCalls++;

        return const <NearbyPassengerDriverProjection>[
          NearbyPassengerDriverProjection(
            latitude: 41.0082,
            longitude: 28.9784,
            updatedAtMillis: 1000,
          ),
        ];
      },
      periodicTimerFactory: (duration, callback) {
        expect(duration, passengerNearbyDriverPollInterval);

        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    addTearDown(controller.dispose);
    addTearDown(ride.dispose);

    controller.start();

    await _flushAsync();

    expect(controller.isActive, isTrue);
    expect(controller.isUpdating, isFalse);
    expect(controller.errorCode, isNull);
    expect(loadCalls, 1);
    expect(timers, hasLength(1));
    expect(timers.single.isActive, isTrue);

    expect(controller.projections, hasLength(1));
    expect(controller.projections.single.latitude, 41.0082);
    expect(controller.projections.single.longitude, 28.9784);
    expect(controller.projections.single.updatedAtMillis, 1000);
  });

  test(
    'does not discover for non-matching assigned or terminal states',
    () async {
      for (final status in <RideStatus>[
        RideStatus.driverEnRoute,
        RideStatus.driverArrived,
        RideStatus.inProgress,
        RideStatus.completed,
        RideStatus.cancelled,
        RideStatus.expired,
      ]) {
        final ride = _RideHarness(rideId: 'ride-$status', status: status);

        var loadCalls = 0;
        var timerCalls = 0;

        final controller = PassengerNearbyDriverController(
          rideListenable: ride,
          rideId: () => ride.rideId,
          rideStatus: () => ride.status,
          loader: () async {
            loadCalls++;
            return const <NearbyPassengerDriverProjection>[];
          },
          periodicTimerFactory: (_, _) {
            timerCalls++;
            return _FakeTimer((_) {});
          },
        );

        controller.start();

        await _flushAsync();

        expect(controller.isActive, isFalse, reason: 'status=$status');

        expect(controller.projections, isEmpty, reason: 'status=$status');

        expect(loadCalls, 0, reason: 'status=$status');

        expect(timerCalls, 0, reason: 'status=$status');

        controller.dispose();
        ride.dispose();
      }
    },
  );

  test('matching transition starts discovery and periodic refresh', () async {
    final ride = _RideHarness();

    final timers = <_FakeTimer>[];
    var loadCalls = 0;

    final controller = PassengerNearbyDriverController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      loader: () async {
        loadCalls++;

        return <NearbyPassengerDriverProjection>[
          NearbyPassengerDriverProjection(
            latitude: 41,
            longitude: 29,
            updatedAtMillis: loadCalls,
          ),
        ];
      },
      periodicTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    addTearDown(controller.dispose);
    addTearDown(ride.dispose);

    controller.start();

    expect(loadCalls, 0);
    expect(controller.isActive, isFalse);

    ride.update(rideId: 'ride-1', status: RideStatus.matching);

    await _flushAsync();

    expect(loadCalls, 1);
    expect(controller.isActive, isTrue);
    expect(timers, hasLength(1));

    timers.single.fire();

    await _flushAsync();

    expect(loadCalls, 2);
    expect(controller.projections.single.updatedAtMillis, 2);
  });

  test(
    'assignment clears approximate projections and cancels polling',
    () async {
      final ride = _RideHarness(rideId: 'ride-1', status: RideStatus.matching);

      final timers = <_FakeTimer>[];

      final controller = PassengerNearbyDriverController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        loader: () async => const <NearbyPassengerDriverProjection>[
          NearbyPassengerDriverProjection(
            latitude: 41,
            longitude: 29,
            updatedAtMillis: 1,
          ),
        ],
        periodicTimerFactory: (_, callback) {
          final timer = _FakeTimer(callback);
          timers.add(timer);
          return timer;
        },
      );

      addTearDown(controller.dispose);
      addTearDown(ride.dispose);

      controller.start();

      await _flushAsync();

      expect(controller.projections, hasLength(1));
      expect(timers.single.isActive, isTrue);

      ride.update(rideId: 'ride-1', status: RideStatus.driverEnRoute);

      expect(controller.isActive, isFalse);
      expect(controller.projections, isEmpty);
      expect(controller.errorCode, isNull);
      expect(timers.single.isActive, isFalse);
    },
  );

  test('stale matching response cannot reappear after assignment', () async {
    final ride = _RideHarness(rideId: 'ride-1', status: RideStatus.matching);

    final completer = Completer<List<NearbyPassengerDriverProjection>>();

    final controller = PassengerNearbyDriverController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      loader: () => completer.future,
      periodicTimerFactory: (_, callback) => _FakeTimer(callback),
    );

    addTearDown(controller.dispose);
    addTearDown(ride.dispose);

    controller.start();

    expect(controller.isActive, isTrue);
    expect(controller.isUpdating, isTrue);

    ride.update(rideId: 'ride-1', status: RideStatus.driverEnRoute);

    expect(controller.isActive, isFalse);
    expect(controller.projections, isEmpty);

    completer.complete(const <NearbyPassengerDriverProjection>[
      NearbyPassengerDriverProjection(
        latitude: 41,
        longitude: 29,
        updatedAtMillis: 1,
      ),
    ]);

    await _flushAsync();

    expect(controller.isActive, isFalse);
    expect(controller.projections, isEmpty);
  });

  test('discovery error fails closed and clears prior projections', () async {
    final ride = _RideHarness(rideId: 'ride-1', status: RideStatus.matching);

    final timers = <_FakeTimer>[];
    var loadCalls = 0;

    final controller = PassengerNearbyDriverController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      loader: () async {
        loadCalls++;

        if (loadCalls == 1) {
          return const <NearbyPassengerDriverProjection>[
            NearbyPassengerDriverProjection(
              latitude: 41,
              longitude: 29,
              updatedAtMillis: 1,
            ),
          ];
        }

        throw const NearbyPassengerDriverDiscoveryException(
          code: 'failed-precondition',
          reason: 'nearby_passenger_discovery_geography_unsupported',
        );
      },
      periodicTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    addTearDown(controller.dispose);
    addTearDown(ride.dispose);

    controller.start();
    await _flushAsync();

    expect(controller.projections, hasLength(1));

    timers.single.fire();
    await _flushAsync();

    expect(controller.projections, isEmpty);
    expect(controller.errorCode, 'failed-precondition');
    expect(controller.isUpdating, isFalse);
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _RideHarness extends ChangeNotifier {
  _RideHarness({this.rideId, this.status});

  String? rideId;
  RideStatus? status;

  void update({required String? rideId, required RideStatus? status}) {
    this.rideId = rideId;
    this.status = status;
    notifyListeners();
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function(Timer timer) _callback;

  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) {
      return;
    }

    _tick++;
    _callback(this);
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
