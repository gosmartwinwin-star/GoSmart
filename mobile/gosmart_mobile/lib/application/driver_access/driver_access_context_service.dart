import '../../domain/driver/driver_eligibility_policy.dart';
import '../../domain/driver/driver_profile.dart';
import '../../domain/subscription/driver_access_pass.dart';
import 'driver_access_context.dart';
import 'driver_access_pass_repository.dart';
import 'driver_profile_repository.dart';

class DriverAccessContextService {
  final DriverProfileRepository _profileRepository;
  final DriverAccessPassRepository _passRepository;
  final DriverEligibilityPolicy _eligibilityPolicy;

  const DriverAccessContextService({
    required DriverProfileRepository profileRepository,
    required DriverAccessPassRepository passRepository,
    DriverEligibilityPolicy eligibilityPolicy = const DriverEligibilityPolicy(),
  }) : _profileRepository = profileRepository,
       _passRepository = passRepository,
       _eligibilityPolicy = eligibilityPolicy;

  Future<DriverAccessContext> load({
    required String? authenticatedUserId,
    required String requiredDriverId,
    required DateTime now,
  }) async {
    if (requiredDriverId.trim().isEmpty) {
      throw ArgumentError.value(
        requiredDriverId,
        'requiredDriverId',
        'Boş olamaz.',
      );
    }

    if (authenticatedUserId?.trim().isNotEmpty != true) {
      return _context(
        authenticatedUserId: authenticatedUserId,
        requiredDriverId: requiredDriverId,
        now: now,
      );
    }

    final profile = await _profileRepository.findByAuthenticatedUserId(
      authenticatedUserId!,
    );
    if (profile == null) {
      return _context(
        authenticatedUserId: authenticatedUserId,
        requiredDriverId: requiredDriverId,
        now: now,
      );
    }

    final pass = await _passRepository.findLatestForDriver(profile.id);
    return _context(
      authenticatedUserId: authenticatedUserId,
      requiredDriverId: requiredDriverId,
      now: now,
      profile: profile,
      pass: pass,
    );
  }

  DriverAccessContext _context({
    required String? authenticatedUserId,
    required String requiredDriverId,
    required DateTime now,
    DriverProfile? profile,
    DriverAccessPass? pass,
  }) {
    final eligibility = _eligibilityPolicy.evaluate(
      authenticatedUserId: authenticatedUserId,
      profile: profile,
      pass: pass,
      requiredDriverId: requiredDriverId,
      now: now,
    );
    return DriverAccessContext(
      profile: profile,
      pass: pass,
      eligibility: eligibility,
    );
  }
}
