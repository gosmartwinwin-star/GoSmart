import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/driver/driver_live_presence_gateway.dart';
import 'package:yoldaal_mobile/application/location/location_access_gateway.dart';
import 'package:yoldaal_mobile/controllers/driver_live_tracking_controller.dart';
import 'package:yoldaal_mobile/domain/return_route/geo_coordinate.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';

void main() {
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
  }

  test('active ride does not start tracking while app is backgrounded', () async {
    final ride = _RideStatusState(RideStatus.driverEnRoute);
    final locations =
        StreamController<DeviceLocation>.broadcast(sync: true);
    final controller = DriverLiveTrackingController(
      rideStatusListenable: ride,
      rideStatus: () => ride.status,
      locationStream: () => locations.stream,
      livePresence: _PresencePublisher(),
      timerFactory: _ManualTimerFactory().create,
    );

    controller.setAppResumed(false);
    controller.start();

    expect(controller.isTracking, isFalse);
    expect(locations.hasListener, isFalse);

    controller.dispose();
    await locations.close();
  });

  test('resume starts tracking deferred while backgrounded', () async {
    final ride = _RideStatusState(RideStatus.driverEnRoute);
    final locations =
        StreamController<DeviceLocation>.broadcast(sync: true);
    final controller = DriverLiveTrackingController(
      rideStatusListenable: ride,
      rideStatus: () => ride.status,
      locationStream: () => locations.stream,
      livePresence: _PresencePublisher(),
      timerFactory: _ManualTimerFactory().create,
    );

    controller.setAppResumed(false);
    controller.start();
    expect(controller.isTracking, isFalse);

    controller.setAppResumed(true);

    expect(controller.isTracking, isTrue);
    expect(locations.hasListener, isTrue);

    controller.dispose();
    await locations.close();
  });

  test('backgrounding does not stop already-running active tracking', () async {
    final ride = _RideStatusState(RideStatus.driverEnRoute);
    final locations =
        StreamController<DeviceLocation>.broadcast(sync: true);
    final controller = DriverLiveTrackingController(
      rideStatusListenable: ride,
      rideStatus: () => ride.status,
      locationStream: () => locations.stream,
      livePresence: _PresencePublisher(),
      timerFactory: _ManualTimerFactory().create,
    )..start();

    expect(controller.isTracking, isTrue);
    expect(locations.hasListener, isTrue);

    controller.setAppResumed(false);

    expect(controller.isTracking, isTrue);
    expect(locations.hasListener, isTrue);

    controller.dispose();
    await locations.close();
  });

  test('terminal ride stops running tracking while backgrounded', () async {
    final ride = _RideStatusState(RideStatus.inProgress);
    final locations =
        StreamController<DeviceLocation>.broadcast(sync: true);
    final controller = DriverLiveTrackingController(
      rideStatusListenable: ride,
      rideStatus: () => ride.status,
      locationStream: () => locations.stream,
      livePresence: _PresencePublisher(),
      timerFactory: _ManualTimerFactory().create,
    )..start();

    expect(controller.isTracking, isTrue);

    controller.setAppResumed(false);
    ride.setStatus(RideStatus.completed);
    await settle();

    expect(controller.isTracking, isFalse);
    expect(locations.hasListener, isFalse);

    controller.dispose();
    await locations.close();
  });

  test('tracking starts only for active ride statuses and terminal stops it', () async {
    final ride = _RideStatusState();
    final locations =
        StreamController<DeviceLocation>.broadcast(sync: true);
    final presence = _PresencePublisher();
    final timers = _ManualTimerFactory();

    final controller = DriverLiveTrackingController(
      rideStatusListenable: ride,
      rideStatus: () => ride.status,
      locationStream: () => locations.stream,
      livePresence: presence,
      timerFactory: timers.create,
    );

    controller.start();

    expect(controller.isTracking, isFalse);
    expect(locations.hasListener, isFalse);

    ride.setStatus(RideStatus.matching);
    expect(controller.isTracking, isFalse);

    ride.setStatus(RideStatus.driverEnRoute);
    expect(controller.isTracking, isTrue);
    expect(locations.hasListener, isTrue);

    locations.add(
      const DeviceLocation(
        latitude: 41.0082,
        longitude: 28.9784,
      ),
    );
    await settle();

    expect(presence.calls, 1);

    ride.setStatus(RideStatus.driverArrived);
    expect(controller.isTracking, isTrue);

    ride.setStatus(RideStatus.inProgress);
    expect(controller.isTracking, isTrue);

    ride.setStatus(RideStatus.completed);
    await settle();

    expect(controller.isTracking, isFalse);
    expect(locations.hasListener, isFalse);

    locations.add(
      const DeviceLocation(
        latitude: 41.02,
        longitude: 29.01,
      ),
    );
    await settle();

    expect(presence.calls, 1);

    controller.dispose();
    await locations.close();
  });

  test('changed locations are network-throttled to five seconds', () async {
    final ride = _RideStatusState(
      RideStatus.driverEnRoute,
    );
    final locations =
        StreamController<DeviceLocation>.broadcast(sync: true);
    final presence = _PresencePublisher();
    final timers = _ManualTimerFactory();

    var now = DateTime.utc(2026, 9, 1, 12);

    final controller = DriverLiveTrackingController(
      rideStatusListenable: ride,
      rideStatus: () => ride.status,
      locationStream: () => locations.stream,
      livePresence: presence,
      now: () => now,
      timerFactory: timers.create,
    )..start();

    locations.add(
      const DeviceLocation(
        latitude: 41.0,
        longitude: 29.0,
      ),
    );
    await settle();

    expect(presence.calls, 1);

    now = now.add(const Duration(seconds: 1));

    locations.add(
      const DeviceLocation(
        latitude: 41.001,
        longitude: 29.001,
      ),
    );
    await settle();

    expect(presence.calls, 1);

    expect(
      timers.hasActive(
        const Duration(seconds: 4),
      ),
      isTrue,
    );

    now = now.add(const Duration(seconds: 4));

    timers.fire(
      const Duration(seconds: 4),
    );
    await settle();

    expect(presence.calls, 2);

    expect(
      presence.lastLocation?.latitude,
      41.001,
    );

    expect(
      presence.lastLocation?.longitude,
      29.001,
    );

    controller.dispose();
    await locations.close();
  });

  test('stationary latest valid location heartbeats no later than fifteen seconds', () async {
    final ride = _RideStatusState(
      RideStatus.driverEnRoute,
    );

    final locations =
        StreamController<DeviceLocation>.broadcast(sync: true);

    final presence = _PresencePublisher();
    final timers = _ManualTimerFactory();

    var now = DateTime.utc(2026, 9, 1, 12);

    final controller = DriverLiveTrackingController(
      rideStatusListenable: ride,
      rideStatus: () => ride.status,
      locationStream: () => locations.stream,
      livePresence: presence,
      now: () => now,
      timerFactory: timers.create,
    )..start();

    locations.add(
      const DeviceLocation(
        latitude: 41.0082,
        longitude: 28.9784,
      ),
    );
    await settle();

    expect(presence.calls, 1);

    expect(
      timers.hasActive(
        driverLiveTrackingHeartbeatInterval,
      ),
      isTrue,
    );

    now = now.add(
      driverLiveTrackingHeartbeatInterval,
    );

    timers.fire(
      driverLiveTrackingHeartbeatInterval,
    );
    await settle();

    expect(presence.calls, 2);

    expect(
      presence.lastLocation?.latitude,
      41.0082,
    );

    expect(
      presence.lastLocation?.longitude,
      28.9784,
    );

    controller.dispose();
    await locations.close();
  });

  test('null ride status cancels stream and heartbeat', () async {
    final ride = _RideStatusState(
      RideStatus.inProgress,
    );

    final locations =
        StreamController<DeviceLocation>.broadcast(sync: true);

    final presence = _PresencePublisher();
    final timers = _ManualTimerFactory();

    final controller = DriverLiveTrackingController(
      rideStatusListenable: ride,
      rideStatus: () => ride.status,
      locationStream: () => locations.stream,
      livePresence: presence,
      timerFactory: timers.create,
    )..start();

    locations.add(
      const DeviceLocation(
        latitude: 41.01,
        longitude: 29.01,
      ),
    );
    await settle();

    expect(presence.calls, 1);

    ride.setStatus(null);
    await settle();

    expect(controller.isTracking, isFalse);
    expect(locations.hasListener, isFalse);
    expect(timers.activeCount, 0);

    timers.fireAll();
    await settle();

    expect(presence.calls, 1);

    controller.dispose();
    await locations.close();
  });

  test('location stream error fails closed and stops stale heartbeats', () async {
    final ride = _RideStatusState(
      RideStatus.driverEnRoute,
    );

    final locations =
        StreamController<DeviceLocation>.broadcast(sync: true);

    final presence = _PresencePublisher();
    final timers = _ManualTimerFactory();

    final controller = DriverLiveTrackingController(
      rideStatusListenable: ride,
      rideStatus: () => ride.status,
      locationStream: () => locations.stream,
      livePresence: presence,
      timerFactory: timers.create,
    )..start();

    locations.add(
      const DeviceLocation(
        latitude: 41.01,
        longitude: 29.01,
      ),
    );
    await settle();

    expect(presence.calls, 1);

    locations.addError(
      StateError('location stream unavailable'),
    );
    await settle();

    expect(controller.isTracking, isFalse);
    expect(locations.hasListener, isFalse);
    expect(timers.activeCount, 0);

    controller.dispose();
    await locations.close();
  });
}

class _RideStatusState extends ChangeNotifier {
  _RideStatusState([this.status]);

  RideStatus? status;

  void setStatus(RideStatus? value) {
    status = value;
    notifyListeners();
  }
}

class _PresencePublisher implements DriverLivePresenceGateway {
  int calls = 0;
  GeoCoordinate? lastLocation;

  @override
  Future<DriverLivePresencePublishResult> publish({
    required GeoCoordinate location,
  }) async {
    calls += 1;
    lastLocation = location;

    return DriverLivePresencePublishResult(
      updatedAtMillis: calls,
    );
  }
}

class _ManualTimerFactory {
  final List<_ManualTimer> timers =
      <_ManualTimer>[];

  Timer create(
    Duration duration,
    void Function() callback,
  ) {
    final timer = _ManualTimer(
      duration,
      callback,
    );

    timers.add(timer);
    return timer;
  }

  int get activeCount =>
      timers.where((timer) => timer.isActive).length;

  bool hasActive(Duration duration) =>
      timers.any(
        (timer) =>
            timer.isActive &&
            timer.duration == duration,
      );

  void fire(Duration duration) {
    final timer = timers.firstWhere(
      (candidate) =>
          candidate.isActive &&
          candidate.duration == duration,
    );

    timer.fire();
  }

  void fireAll() {
    for (final timer in List<_ManualTimer>.of(timers)) {
      timer.fire();
    }
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(
    this.duration,
    this._callback,
  );

  final Duration duration;
  final void Function() _callback;

  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) {
      return;
    }

    _active = false;
    _tick += 1;
    _callback();
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
