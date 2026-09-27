import '../domain/ride_support_case.dart';

abstract interface class RideSupportAdminReadGateway {
  Future<RideSupportCasePage> list({
    int pageSize = 20,
    RideSupportCaseCursor? cursor,
  });
}

abstract interface class RideSupportAdminTransitionGateway {
  Future<RideSupportCaseTransitionResult> transition({
    required String rideId,
    required String caseId,
    required RideSupportCaseStatus targetStatus,
    required DateTime expectedUpdatedAt,
    required String requestId,
  });
}
