import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/ride/ride_live_tracking_gateway.dart';
import '../domain/return_route/geo_coordinate.dart';
import '../domain/ride/canonical_ride.dart';

const passengerRideLiveTrackingPollInterval =
    Duration(seconds: 5);

typedef PassengerRideLiveTrackingRideIdReader =
    String? Function();

typedef PassengerRideLiveTrackingStatusReader =
    RideStatus? Function();

typedef PassengerRideLiveTrackingPeriodicTimerFactory =
    Timer Function(
      Duration duration,
      void Function(Timer timer) callback,
    );

class PassengerRideLiveTrackingController
    extends ChangeNotifier {
  PassengerRideLiveTrackingController({
    required Listenable rideListenable,
    required PassengerRideLiveTrackingRideIdReader rideId,
    required PassengerRideLiveTrackingStatusReader rideStatus,
    required RideLiveTrackingGateway gateway,
    PassengerRideLiveTrackingPeriodicTimerFactory?
    periodicTimerFactory,
  }) : _rideListenable = rideListenable,
       _rideId = rideId,
       _rideStatus = rideStatus,
       _gateway = gateway,
       _periodicTimerFactory =
           periodicTimerFactory ?? Timer.periodic;

  static const Set<RideStatus> _activeStatuses =
      <RideStatus>{
        RideStatus.driverEnRoute,
        RideStatus.driverArrived,
        RideStatus.inProgress,
      };

  final Listenable _rideListenable;
  final PassengerRideLiveTrackingRideIdReader _rideId;
  final PassengerRideLiveTrackingStatusReader _rideStatus;
  final RideLiveTrackingGateway _gateway;
  final PassengerRideLiveTrackingPeriodicTimerFactory
  _periodicTimerFactory;

  Timer? _pollTimer;
  RideLiveTrackingSnapshot? _snapshot;

  String? _trackedRideId;
  RideStatus? _trackedStatus;

  bool _started = false;
  bool _active = false;
  bool _updating = false;
  bool _inFlight = false;
  bool _pendingImmediateRead = false;
  bool _disposed = false;

  int _generation = 0;

  bool get isActive => _active && !_disposed;

  bool get isUpdating =>
      isActive && _updating;

  GeoCoordinate? get driverLocation =>
      _snapshot?.driverLocation;

  int? get etaSeconds =>
      _snapshot?.etaSeconds;

  int? get updatedAtMillis =>
      _snapshot?.updatedAtMillis;

  int? get etaUpdatedAtMillis =>
      _snapshot?.etaUpdatedAtMillis;

  void start() {
    if (_started || _disposed) {
      return;
    }

    _started = true;

    _rideListenable.addListener(
      _syncRideState,
    );

    _syncRideState();
  }

  void _syncRideState() {
    if (_disposed) {
      return;
    }

    final rideId = _rideId();
    final status = _rideStatus();

    final shouldTrack =
        rideId != null &&
        rideId.isNotEmpty &&
        status != null &&
        _activeStatuses.contains(status);

    if (!shouldTrack) {
      _stopTracking();
      return;
    }

    if (!_active ||
        _trackedRideId != rideId ||
        _trackedStatus != status) {
      _beginTracking(
        rideId: rideId,
        status: status,
      );
    }
  }

  void _beginTracking({
    required String rideId,
    required RideStatus status,
  }) {
    _generation += 1;

    _pollTimer?.cancel();

    _active = true;
    _trackedRideId = rideId;
    _trackedStatus = status;
    _snapshot = null;
    _updating = true;

    _pollTimer = _periodicTimerFactory(
      passengerRideLiveTrackingPollInterval,
      (_) {
        if (!_inFlight) {
          unawaited(_readCurrent());
        }
      },
    );

    _notify();

    if (_inFlight) {
      _pendingImmediateRead = true;
    } else {
      unawaited(_readCurrent());
    }
  }

  Future<void> _readCurrent() async {
    if (_disposed || !_active || _inFlight) {
      return;
    }

    final rideId = _trackedRideId;
    final status = _trackedStatus;

    if (rideId == null || status == null) {
      _stopTracking();
      return;
    }

    final generation = _generation;

    _inFlight = true;

    try {
      final result = await _gateway.getTracking(
        rideId: rideId,
      );

      if (_disposed ||
          !_active ||
          generation != _generation ||
          rideId != _trackedRideId ||
          status != _trackedStatus) {
        return;
      }

      if (!_isAuthoritativeForStatus(
        result,
        status,
      )) {
        _snapshot = null;
        _updating = true;
        _notify();
        return;
      }

      _snapshot = result;
      _updating = false;
      _notify();
    } catch (_) {
      if (_disposed ||
          !_active ||
          generation != _generation) {
        return;
      }

      _snapshot = null;
      _updating = true;
      _notify();
    } finally {
      _inFlight = false;

      if (!_disposed &&
          _active &&
          _pendingImmediateRead) {
        _pendingImmediateRead = false;
        unawaited(_readCurrent());
      }
    }
  }

  static bool _isAuthoritativeForStatus(
    RideLiveTrackingSnapshot snapshot,
    RideStatus status,
  ) {
    if (snapshot.driverLocation == null ||
        snapshot.updatedAtMillis == null) {
      return false;
    }

    if (status == RideStatus.driverArrived) {
      return true;
    }

    return snapshot.etaSeconds != null &&
        snapshot.etaUpdatedAtMillis != null;
  }

  void _stopTracking() {
    final hadVisibleState =
        _active ||
        _snapshot != null ||
        _updating ||
        _pollTimer != null;

    _generation += 1;

    _pollTimer?.cancel();
    _pollTimer = null;

    _active = false;
    _trackedRideId = null;
    _trackedStatus = null;
    _snapshot = null;
    _updating = false;
    _pendingImmediateRead = false;

    if (hadVisibleState) {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    if (_started) {
      _rideListenable.removeListener(
        _syncRideState,
      );
    }

    _stopTracking();
    _disposed = true;

    super.dispose();
  }
}
