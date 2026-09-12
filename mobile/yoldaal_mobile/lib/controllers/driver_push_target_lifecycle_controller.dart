import 'dart:async';

import '../services/driver_push_target_registration_service.dart';

abstract interface class DriverPushTargetLifecycle {
  void setEligible(bool eligible);

  void dispose();
}

class DriverPushTargetLifecycleController
    implements DriverPushTargetLifecycle {
  DriverPushTargetLifecycleController({
    required DriverPushTargetRegistrationService registration,
    required DriverPushTargetPlatform platform,
  }) : _registration = registration,
       _platform = platform {
    _installationIdSubscription =
        _registration.installationIdChanges.listen(
          _handleInstallationIdChanged,
          onError: (Object _) {},
        );
  }

  final DriverPushTargetRegistrationService _registration;
  final DriverPushTargetPlatform _platform;

  StreamSubscription<String>? _installationIdSubscription;

  Future<void> _tail = Future<void>.value();

  bool _eligible = false;
  bool _disposed = false;
  int _generation = 0;

  bool get eligible => _eligible;

  Future<void> get idle => _tail;

  @override
  void setEligible(bool eligible) {
    if (_disposed || _eligible == eligible) {
      return;
    }

    _eligible = eligible;
    _generation += 1;

    if (_eligible) {
      _enqueueCurrentInstallation(
        generation: _generation,
      );
    }
  }

  void _handleInstallationIdChanged(String fid) {
    if (_disposed || !_eligible) {
      return;
    }

    _enqueueInstallationId(
      fid: fid,
      generation: _generation,
    );
  }

  void _enqueueCurrentInstallation({
    required int generation,
  }) {
    _enqueue(
      generation: generation,
      operation: () async {
        await _registration.registerCurrentInstallation(
          platform: _platform,
        );
      },
    );
  }

  void _enqueueInstallationId({
    required String fid,
    required int generation,
  }) {
    _enqueue(
      generation: generation,
      operation: () async {
        await _registration.registerInstallationId(
          fid: fid,
          platform: _platform,
        );
      },
    );
  }

  void _enqueue({
    required int generation,
    required Future<void> Function() operation,
  }) {
    _tail = _tail.then((_) async {
      if (_disposed ||
          !_eligible ||
          generation != _generation) {
        return;
      }

      try {
        await operation();
      } catch (_) {
        // Push-target registration is a fail-soft background capability.
        // Authoritative ride/match access never depends on this side effect.
      }
    });
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _eligible = false;
    _generation += 1;

    final subscription = _installationIdSubscription;
    _installationIdSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }
}
