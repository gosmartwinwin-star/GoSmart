import '../../domain/matching/matching_policy.dart';
import '../../domain/return_route/geo_coordinate.dart';
import '../../domain/return_route/route_anchor_result.dart';

abstract interface class RouteDeviationGateway {
  Future<RouteDeviationResult> compute({
    required RouteAnchorResult anchors,
    required GeoCoordinate pickup,
    required GeoCoordinate dropoff,
  });
}
