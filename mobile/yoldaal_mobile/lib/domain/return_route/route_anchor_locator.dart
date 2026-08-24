import 'driver_return_route.dart';
import 'geo_coordinate.dart';
import 'geo_distance.dart';
import 'route_anchor_result.dart';

class RouteAnchorLocator {
  const RouteAnchorLocator();

  RouteAnchorResult locate({
    required DriverReturnRoute route,
    required GeoCoordinate pickup,
    required GeoCoordinate dropoff,
  }) {
    if (!route.hasCalculatedRoute || route.routePointCount < 2) {
      throw StateError('Hesaplanmış dönüş rotası bulunamadı.');
    }

    var pickupRouteIndex = 0;
    var dropoffRouteIndex = 0;
    var pickupAnchor = route.pointAt(0);
    var dropoffAnchor = pickupAnchor;
    var pickupProximity = GeoDistance.betweenMeters(pickup, pickupAnchor);
    var dropoffProximity = GeoDistance.betweenMeters(dropoff, dropoffAnchor);

    for (var index = 1; index < route.routePointCount; index++) {
      final routePoint = route.pointAt(index);
      final pickupCandidate = GeoDistance.betweenMeters(pickup, routePoint);
      final dropoffCandidate = GeoDistance.betweenMeters(dropoff, routePoint);

      if (pickupCandidate < pickupProximity) {
        pickupRouteIndex = index;
        pickupAnchor = routePoint;
        pickupProximity = pickupCandidate;
      }
      if (dropoffCandidate < dropoffProximity) {
        dropoffRouteIndex = index;
        dropoffAnchor = routePoint;
        dropoffProximity = dropoffCandidate;
      }
    }

    return RouteAnchorResult(
      pickupRouteIndex: pickupRouteIndex,
      dropoffRouteIndex: dropoffRouteIndex,
      pickupAnchor: pickupAnchor,
      dropoffAnchor: dropoffAnchor,
      pickupAnchorProximityMeters: pickupProximity,
      dropoffAnchorProximityMeters: dropoffProximity,
    );
  }
}
