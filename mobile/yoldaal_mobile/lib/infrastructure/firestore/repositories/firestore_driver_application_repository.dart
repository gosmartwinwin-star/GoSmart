import '../../../application/driver_application/driver_application_repository.dart';
import '../../../domain/driver_application/driver_application_review.dart';
import '../../../services/driver_application_review_service.dart';

@Deprecated('Use DriverApplicationReviewService directly.')
class FirestoreDriverApplicationRepository
    implements DriverApplicationRepository {
  FirestoreDriverApplicationRepository({DriverApplicationRepository? delegate})
    : _delegate = delegate ?? DriverApplicationReviewService();

  final DriverApplicationRepository _delegate;

  @override
  Future<DriverApplicationReview?> findForAuthenticatedUser() =>
      _delegate.findForAuthenticatedUser();
}
