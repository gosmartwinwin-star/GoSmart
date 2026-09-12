import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/driver/driver_live_presence_gateway.dart';
import '../application/location/location_access_gateway.dart';
import '../domain/return_route/geo_coordinate.dart';
import '../domain/ride/canonical_ride.dart';

const driverLiveTrackingPublishInterval = Duration(seconds: 5);
const driverLiveTrackingHeartbeatInterval = Duration(seconds: 15);

typedef DriverLiveTrackingRideStatusReader = RideStatus? Function();
typedef DriverLiveTrackingLocationStream =
    Stream<DeviceLocation> Function();
typedef DriverLiveTrackingNow = DateTime Function();
typedef DriverLiveTrackingTimerFactory =
    Timer Function(Duration duration, void Function() callback);

class DriverLiveTrackingController {
  DriverLiveTrackingController({
    required Listenable rideStatusListenable,
    required DriverLiveTrackingRideStatusReader rideStatus,
    required DriverLiveTrackingLocationStream locationStream,
    required DriverLivePresenceGateway livePresence,
    DriverLiveTrackingNow? now,
    DriverLiveTrackingTimerFactory? timerFactory,
  }) : _rideStatusListenable = rideStatusListenable,
       _rideStatus = rideStatus,
       _locationStream = locationStream,
       _livePresence = livePresence,
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? _defaultTimerFactory;

  static const Set<RideStatus> _activeStatuses = <RideStatus>{
    RideStatus.driverEnRoute,
    RideStatus.driverArrived,
    RideStatus.inProgress,
  };

  final Listenable _rideStatusListenable;
  final DriverLiveTrackingRideStatusReader _rideStatus;
  final DriverLiveTrackingLocationStream _locationStream;
  final DriverLivePresenceGateway _livePresence;
  final DriverLiveTrackingNow _now;
  final DriverLiveTrackingTimerFactory _timerFactory;

  StreamSubscription<DeviceLocation>? _locationSubscription;
  Timer? _throttleTimer;
  Timer? _heartbeatTimer;

  DeviceLocation? _latestLocation;
  DeviceLocation? _lastPublishedLocation;
  DateTime? _lastPublishStartedAt;

  bool _started = false;
  bool _active = false;
  bool _publishing = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isTracking => _active && !_disposed;

  void start() {
    if (_started || _disposed) {
      return;
    }

    _started = true;
    _rideStatusListenable.addListener(_syncRideState);
    _syncRideState();
  }

  void _syncRideState() {
    if (_disposed) {
      return;
    }

    final shouldTrack =
        _activeStatuses.contains(_rideStatus());

    if (shouldTrack) {
      if (!_active) {
        _startTracking();
      }
      return;
    }

    if (_active || _locationSubscription != null) {
      _stopTracking();
    }
  }

  void _startTracking() {
    if (_disposed || _active) {
      return;
    }

    _active = true;
    _generation += 1;
    _latestLocation = null;
    _lastPublishedLocation = null;
    _lastPublishStartedAt = null;

    try {
      _locationSubscription = _locationStream().listen(
        _onLocation,
        onError: (Object _, StackTrace _) {
          _stopTracking();
        },
        onDone: _stopTracking,
      );
    } catch (_) {
      _active = false;
      _generation += 1;
    }
  }

  void _onLocation(DeviceLocation location) {
    if (
        !_active ||
        _disposed ||
        !location.isValid
    ) {
      return;
    }

    _latestLocation = location;
    _queuePublish();
  }

  void _queuePublish({bool force = false}) {
    if (
        !_active ||
        _disposed ||
        _latestLocation == null
    ) {
      return;
    }

    if (
        !force &&
        _sameLocation(
          _latestLocation,
          _lastPublishedLocation,
        )
    ) {
      return;
    }

    if (_publishing) {
      return;
    }

    final now = _now();
    final lastStarted = _lastPublishStartedAt;

    if (lastStarted == null) {
      unawaited(_publishLatest(force: force));
      return;
    }

    final elapsed = now.difference(lastStarted);

    if (elapsed >= driverLiveTrackingPublishInterval) {
      unawaited(_publishLatest(force: force));
      return;
    }

    if (_throttleTimer?.isActive ?? false) {
      return;
    }

    final remaining =
        driverLiveTrackingPublishInterval - elapsed;

    _throttleTimer = _timerFactory(
      remaining,
      () {
        _throttleTimer = null;
        _queuePublish(force: force);
      },
    );
  }

  Future<void> _publishLatest({
    required bool force,
  }) async {
    final location = _latestLocation;

    if (
        !_active ||
        _disposed ||
        _publishing ||
        location == null
    ) {
      return;
    }

    if (
        !force &&
        _sameLocation(
          location,
          _lastPublishedLocation,
        )
    ) {
      return;
    }

    _throttleTimer?.cancel();
    _throttleTimer = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final generation = _generation;

    _publishing = true;
    _lastPublishStartedAt = _now();

    var published = false;

    try {
      await _livePresence.publish(
        location: GeoCoordinate(
          latitude: location.latitude,
          longitude: location.longitude,
        ),
      );

      if (
          _active &&
          !_disposed &&
          generation == _generation
      ) {
        _lastPublishedLocation = location;
        published = true;
      }
    } catch (_) {
      published = false;
    } finally {
      _publishing = false;
    }

    if (!_active || _disposed) {
      return;
    }

    if (generation != _generation) {
      _queuePublish();
      return;
    }

    if (!published) {
      _queuePublish(force: true);
      return;
    }

    _scheduleHeartbeat();

    if (
        !_sameLocation(
          _latestLocation,
          _lastPublishedLocation,
        )
    ) {
      _queuePublish();
    }
  }

  void _scheduleHeartbeat() {
    _heartbeatTimer?.cancel();

    final lastStarted = _lastPublishStartedAt;
    if (lastStarted == null) {
      return;
    }

    final elapsed = _now().difference(lastStarted);

    final remaining =
        elapsed >= driverLiveTrackingHeartbeatInterval
            ? Duration.zero
            : driverLiveTrackingHeartbeatInterval - elapsed;

    _heartbeatTimer = _timerFactory(
      remaining,
      () {
        _heartbeatTimer = null;
        _queuePublish(force: true);
      },
    );
  }

  void _stopTracking() {
    if (
        !_active &&
        _locationSubscription == null &&
        !(_throttleTimer?.isActive ?? false) &&
        !(_heartbeatTimer?.isActive ?? false)
    ) {
      return;
    }

    _active = false;
    _generation += 1;

    final subscription = _locationSubscription;
    _locationSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    _throttleTimer?.cancel();
    _throttleTimer = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _latestLocation = null;
    _lastPublishedLocation = null;
    _lastPublishStartedAt = null;
  }

  static bool _sameLocation(
    DeviceLocation? left,
    DeviceLocation? right,
  ) {
    if (left == null || right == null) {
      return false;
    }

    return left.latitude == right.latitude &&
        left.longitude == right.longitude;
  }

  static Timer _defaultTimerFactory(
    Duration duration,
    void Function() callback,
  ) =>
      Timer(duration, callback);

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    if (_started) {
      _rideStatusListenable.removeListener(
        _syncRideState,
      );
    }

    _stopTracking();
  }
}
