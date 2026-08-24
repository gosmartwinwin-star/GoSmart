import 'driver_access_pass.dart';

class DriverAccessPolicy {
  const DriverAccessPolicy();

  bool canStartNewMatch({
    required DriverAccessPass? pass,
    required DateTime now,
  }) {
    return _hasActiveAccess(pass: pass, now: now);
  }

  bool canPublishReturnRoute({
    required DriverAccessPass? pass,
    required DateTime now,
  }) {
    return _hasActiveAccess(pass: pass, now: now);
  }

  bool canSendOffer({required DriverAccessPass? pass, required DateTime now}) {
    return _hasActiveAccess(pass: pass, now: now);
  }

  bool canContinueAcceptedRide({required bool rideAlreadyAccepted}) {
    return rideAlreadyAccepted;
  }

  bool _hasActiveAccess({
    required DriverAccessPass? pass,
    required DateTime now,
  }) {
    return pass?.isActiveAt(now) ?? false;
  }
}
