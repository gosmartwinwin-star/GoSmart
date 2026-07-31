import '../subscription/driver_access_pass.dart';
import '../subscription/driver_access_policy.dart';
import 'driver_eligibility_rejection_codes.dart';
import 'driver_eligibility_result.dart';
import 'driver_profile.dart';
import 'driver_profile_status.dart';

class DriverEligibilityPolicy {
  final DriverAccessPolicy _accessPolicy;

  const DriverEligibilityPolicy({
    DriverAccessPolicy accessPolicy = const DriverAccessPolicy(),
  }) : _accessPolicy = accessPolicy;

  DriverEligibilityResult evaluate({
    required String? authenticatedUserId,
    required DriverProfile? profile,
    required DriverAccessPass? pass,
    required String requiredDriverId,
    required DateTime now,
  }) {
    final authenticated = authenticatedUserId?.trim().isNotEmpty == true;
    if (!authenticated) {
      return _rejected(
        authenticated: false,
        reason: DriverEligibilityRejectionCodes.authenticationRequired,
      );
    }
    if (profile == null) {
      return _rejected(
        authenticated: true,
        reason: DriverEligibilityRejectionCodes.driverProfileRequired,
      );
    }

    final identityCompatible =
        profile.authUserId == authenticatedUserId &&
        profile.id == requiredDriverId &&
        (pass == null || pass.driverId == profile.id);
    if (!identityCompatible) {
      return _rejected(
        authenticated: true,
        profilePresent: true,
        reason: DriverEligibilityRejectionCodes.driverIdentityMismatch,
      );
    }

    final approvalReason = switch (profile.status) {
      DriverProfileStatus.pendingReview =>
        DriverEligibilityRejectionCodes.driverApprovalRequired,
      DriverProfileStatus.suspended =>
        DriverEligibilityRejectionCodes.driverSuspended,
      DriverProfileStatus.rejected =>
        DriverEligibilityRejectionCodes.driverRejected,
      DriverProfileStatus.deactivated =>
        DriverEligibilityRejectionCodes.driverDeactivated,
      DriverProfileStatus.approved => null,
    };
    if (approvalReason != null) {
      return _rejected(
        authenticated: true,
        profilePresent: true,
        identityCompatible: true,
        reason: approvalReason,
      );
    }

    final subscriptionActive = _accessPolicy.canStartNewMatch(
      pass: pass,
      now: now,
    );
    return DriverEligibilityResult(
      authenticated: true,
      driverProfilePresent: true,
      identityCompatible: true,
      driverApproved: true,
      subscriptionActive: subscriptionActive,
      rejectionReasons: subscriptionActive
          ? const []
          : const [DriverEligibilityRejectionCodes.subscriptionRequired],
    );
  }

  bool canPublishReturnRoute({
    required String? authenticatedUserId,
    required DriverProfile? profile,
    required DriverAccessPass? pass,
    required String requiredDriverId,
    required DateTime now,
  }) => evaluate(
    authenticatedUserId: authenticatedUserId,
    profile: profile,
    pass: pass,
    requiredDriverId: requiredDriverId,
    now: now,
  ).canUseDriverPlatform;

  bool canReceiveMatches({
    required String? authenticatedUserId,
    required DriverProfile? profile,
    required DriverAccessPass? pass,
    required String requiredDriverId,
    required DateTime now,
  }) => canPublishReturnRoute(
    authenticatedUserId: authenticatedUserId,
    profile: profile,
    pass: pass,
    requiredDriverId: requiredDriverId,
    now: now,
  );

  bool canSendOffer({
    required String? authenticatedUserId,
    required DriverProfile? profile,
    required DriverAccessPass? pass,
    required String requiredDriverId,
    required DateTime now,
  }) => canPublishReturnRoute(
    authenticatedUserId: authenticatedUserId,
    profile: profile,
    pass: pass,
    requiredDriverId: requiredDriverId,
    now: now,
  );

  DriverEligibilityResult _rejected({
    required bool authenticated,
    bool profilePresent = false,
    bool identityCompatible = false,
    required String reason,
  }) => DriverEligibilityResult(
    authenticated: authenticated,
    driverProfilePresent: profilePresent,
    identityCompatible: identityCompatible,
    driverApproved: false,
    subscriptionActive: false,
    rejectionReasons: [reason],
  );
}
