import '../../domain/return_route/geo_coordinate.dart';
import 'published_return_route.dart';

abstract interface class PublishReturnRouteGateway {
  Future<PublishedReturnRoute> publish({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
    required int validForSeconds,
  });
}
