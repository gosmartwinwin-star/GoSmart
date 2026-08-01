import '../../domain/driver_application/driver_application_status.dart';

class DriverApplicationSummary {
  final DriverApplicationStatus status;
  final DateTime submittedAt;
  final int submissionVersion;
  const DriverApplicationSummary({
    required this.status,
    required this.submittedAt,
    required this.submissionVersion,
  });
}

abstract interface class DriverApplicationRepository {
  Future<DriverApplicationSummary?> findForAuthenticatedUser(String userId);
}
