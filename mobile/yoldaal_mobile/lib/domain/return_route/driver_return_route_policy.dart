import 'driver_return_route.dart';
import 'driver_return_route_status.dart';

class DriverReturnRoutePolicy {
  const DriverReturnRoutePolicy();

  bool canPublish({
    required DriverReturnRoute route,
    required bool subscriptionActive,
    required DateTime now,
  }) {
    return _canUseForNewMatches(
      route: route,
      subscriptionActive: subscriptionActive,
      now: now,
    );
  }

  bool canReceiveMatches({
    required DriverReturnRoute route,
    required bool subscriptionActive,
    required DateTime now,
  }) {
    return _canUseForNewMatches(
      route: route,
      subscriptionActive: subscriptionActive,
      now: now,
    );
  }

  bool canPause({required DriverReturnRoute route}) {
    return route.status == DriverReturnRouteStatus.active;
  }

  bool canResume({
    required DriverReturnRoute route,
    required bool subscriptionActive,
    required DateTime now,
  }) {
    return route.status == DriverReturnRouteStatus.paused &&
        subscriptionActive &&
        _hasUnexpiredWindow(route: route, now: now) &&
        route.hasCalculatedRoute;
  }

  bool canComplete({required DriverReturnRoute route}) {
    return route.status == DriverReturnRouteStatus.active ||
        route.status == DriverReturnRouteStatus.paused;
  }

  bool canActivateNewRoute({
    required Iterable<DriverReturnRoute> existingRoutes,
    required String driverId,
    required DateTime now,
  }) {
    for (final route in existingRoutes) {
      if (route.driverId == driverId && route.isActiveAt(now)) {
        return false;
      }
    }

    return true;
  }

  bool _canUseForNewMatches({
    required DriverReturnRoute route,
    required bool subscriptionActive,
    required DateTime now,
  }) {
    return subscriptionActive &&
        route.isActiveAt(now) &&
        route.hasCalculatedRoute;
  }

  bool _hasUnexpiredWindow({
    required DriverReturnRoute route,
    required DateTime now,
  }) {
    final activation = route.activatedAt;
    final expiration = route.expiresAt;

    return activation != null && expiration != null && now.isBefore(expiration);
  }
}
