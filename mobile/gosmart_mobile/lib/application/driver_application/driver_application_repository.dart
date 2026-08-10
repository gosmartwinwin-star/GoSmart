import '../../domain/driver_application/driver_application_review.dart';

abstract interface class DriverApplicationRepository {
  Future<DriverApplicationReview?> findForAuthenticatedUser();
}
