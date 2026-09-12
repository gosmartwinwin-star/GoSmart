import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/ride/canonical_ride.dart';
import '../services/nearby_passenger_driver_service.dart';

const passengerNearbyDriverPollInterval = Duration(seconds: 5);

typedef PassengerNearbyDriverRideIdReader = String? Function();
typedef PassengerNearbyDriverStatusReader = RideStatus? Function();
typedef PassengerNearbyDriverLoader =
    Future<List<NearbyPassengerDriverProjection>> Function();

typedef PassengerNearbyDriverPeriodicTimerFactory =
    Timer Function(Duration duration, void Function(Timer timer) callback);

class PassengerNearbyDriverController extends ChangeNotifier {
  PassengerNearbyDriverController({
    required Listenable rideListenable,
    required PassengerNearbyDriverRideIdReader rideId,
    required PassengerNearbyDriverStatusReader rideStatus,
    required PassengerNearbyDriverLoader loader,
    PassengerNearbyDriverPeriodicTimerFactory? periodicTimerFactory,
  }) : _rideListenable = rideListenable,
       _rideId = rideId,
       _rideStatus = rideStatus,
       _loader = loader,
       _periodicTimerFactory = periodicTimerFactory ?? Timer.periodic;

  final Listenable _rideListenable;
  final PassengerNearbyDriverRideIdReader _rideId;
  final PassengerNearbyDriverStatusReader _rideStatus;
  final PassengerNearbyDriverLoader _loader;
  final PassengerNearbyDriverPeriodicTimerFactory _periodicTimerFactory;

  Timer? _pollTimer;

  List<NearbyPassengerDriverProjection> _projections =
      const <NearbyPassengerDriverProjection>[];

  String? _trackedRideId;
  String? _errorCode;

  bool _started = false;
  bool _active = false;
  bool _updating = false;
  bool _inFlight = false;
  bool _pendingImmediateRead = false;
  bool _disposed = false;

  int _generation = 0;

  List<NearbyPassengerDriverProjection> get projections => _projections;

  String? get errorCode => _errorCode;

  bool get isActive => _active;

  bool get isUpdating => _updating;

  void start() {
    if (_disposed) {
      throw StateError('PassengerNearbyDriverController is disposed.');
    }

    if (_started) {
      return;
    }

    _started = true;
    _rideListenable.addListener(_syncRideState);
    _syncRideState();
  }

  void _syncRideState() {
    if (_disposed || !_started) {
      return;
    }

    final rideId = _rideId();
    final status = _rideStatus();

    final shouldTrack =
        rideId != null && rideId.isNotEmpty && status == RideStatus.matching;

    if (!shouldTrack) {
      _stopTracking();
      return;
    }

    if (!_active || _trackedRideId != rideId) {
      _beginTracking(rideId);
    }
  }

  void _beginTracking(String rideId) {
    _generation += 1;

    _pollTimer?.cancel();

    _active = true;
    _trackedRideId = rideId;
    _projections = const <NearbyPassengerDriverProjection>[];
    _errorCode = null;
    _updating = true;

    _pollTimer = _periodicTimerFactory(passengerNearbyDriverPollInterval, (_) {
      if (!_inFlight) {
        unawaited(_readCurrent());
      }
    });

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

    final generation = _generation;

    _inFlight = true;

    try {
      final result = await _loader();

      if (_disposed || !_active || generation != _generation) {
        return;
      }

      _projections = List<NearbyPassengerDriverProjection>.unmodifiable(result);

      _errorCode = null;
      _updating = false;

      _notify();
    } on NearbyPassengerDriverDiscoveryException catch (error) {
      if (_disposed || !_active || generation != _generation) {
        return;
      }

      _projections = const <NearbyPassengerDriverProjection>[];
      _errorCode = error.code;
      _updating = false;

      _notify();
    } catch (_) {
      if (_disposed || !_active || generation != _generation) {
        return;
      }

      _projections = const <NearbyPassengerDriverProjection>[];
      _errorCode = 'unavailable';
      _updating = false;

      _notify();
    } finally {
      _inFlight = false;

      if (!_disposed && _active && _pendingImmediateRead) {
        _pendingImmediateRead = false;
        unawaited(_readCurrent());
      }
    }
  }

  void _stopTracking() {
    final hadVisibleState =
        _active ||
        _projections.isNotEmpty ||
        _errorCode != null ||
        _updating ||
        _pollTimer != null;

    _generation += 1;

    _pollTimer?.cancel();
    _pollTimer = null;

    _active = false;
    _trackedRideId = null;
    _projections = const <NearbyPassengerDriverProjection>[];
    _errorCode = null;
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
      _rideListenable.removeListener(_syncRideState);
    }

    _stopTracking();
    _disposed = true;

    super.dispose();
  }
}
