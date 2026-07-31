import '../../domain/driver/driver_eligibility_result.dart';
import '../../domain/driver/driver_profile.dart';
import '../../domain/subscription/driver_access_pass.dart';

class DriverAccessContext {
  final DriverProfile? profile;
  final DriverAccessPass? pass;
  final DriverEligibilityResult eligibility;

  const DriverAccessContext({
    required this.profile,
    required this.pass,
    required this.eligibility,
  });

  bool get canUseDriverPlatform => eligibility.canUseDriverPlatform;
}
