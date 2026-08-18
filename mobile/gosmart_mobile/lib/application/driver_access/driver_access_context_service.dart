import '../../domain/driver/driver_eligibility_policy.dart';
import '../../domain/driver/driver_profile.dart';
import '../../domain/subscription/driver_access_mode.dart';
import '../../domain/subscription/driver_access_pass.dart';
import 'driver_access_context.dart';
import 'driver_access_mode_repository.dart';
import 'driver_access_pass_repository.dart';
import 'driver_profile_repository.dart';

class DriverAccessContextService {
  final DriverProfileRepository _profileRepository;
  final DriverAccessPassRepository _passRepository;
  final DriverAccessModeRepository _modeRepository;
  final DriverEligibilityPolicy _eligibilityPolicy;

  const DriverAccessContextService({
    required DriverProfileRepository profileRepository,
    required DriverAccessPassRepository passRepository,
    DriverAccessModeRepository modeRepository =
        const PaidDriverAccessModeRepository(),
    DriverEligibilityPolicy eligibilityPolicy = const DriverEligibilityPolicy(),
  }) : _profileRepository = profileRepository,
       _passRepository = passRepository,
       _modeRepository = modeRepository,
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

    final accessMode = await _loadAccessModeFailClosed();

    final pass = accessMode.requiresPass
        ? await _passRepository.findLatestForDriver(profile.id)
        : null;

    return _context(
      authenticatedUserId: authenticatedUserId,
      requiredDriverId: requiredDriverId,
      now: now,
      profile: profile,
      pass: pass,
      accessMode: accessMode,
    );
  }

  Future<DriverAccessMode> _loadAccessModeFailClosed() async {
    try {
      return await _modeRepository.load();
    } catch (_) {
      return DriverAccessMode.paid;
    }
  }

  DriverAccessContext _context({
    required String? authenticatedUserId,
    required String requiredDriverId,
    required DateTime now,
    DriverProfile? profile,
    DriverAccessPass? pass,
    DriverAccessMode accessMode = DriverAccessMode.paid,
  }) {
    final eligibility = _eligibilityPolicy.evaluate(
      authenticatedUserId: authenticatedUserId,
      profile: profile,
      pass: pass,
      accessMode: accessMode,
      requiredDriverId: requiredDriverId,
      now: now,
    );
    return DriverAccessContext(
      profile: profile,
      pass: pass,
      accessMode: accessMode,
      eligibility: eligibility,
    );
  }
}
