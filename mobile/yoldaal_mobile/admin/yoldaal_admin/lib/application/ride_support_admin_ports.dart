import '../domain/ride_support_case.dart';

abstract interface class RideSupportAdminReadGateway {
  Future<RideSupportCasePage> list({
    int pageSize = 20,
    RideSupportCaseCursor? cursor,
  });
}
