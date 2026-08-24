import 'published_return_route.dart';

abstract interface class ActiveReturnRouteRecoveryGateway {
  Future<PublishedReturnRoute?> recover();
}
