import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/driver/driver_eligibility_policy.dart';
import 'package:gosmart_mobile/domain/driver/driver_eligibility_rejection_codes.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_mode.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 18);

  DriverProfile profile({
    DriverProfileStatus status = DriverProfileStatus.approved,
  }) {
    return DriverProfile(
      id: 'driver-1',
      authUserId: 'user-1',
      status: status,
      createdAt: now.subtract(const Duration(days: 2)),
      approvedAt: status == DriverProfileStatus.pendingReview
          ? null
          : now.subtract(const Duration(days: 1)),
      suspendedAt: status == DriverProfileStatus.suspended
          ? now.subtract(const Duration(hours: 1))
          : null,
    );
  }

  DriverAccessPass activePass() {
    return DriverAccessPass(
      id: 'pass-1',
      driverId: 'driver-1',
      plan: DriverPassPlan.daily,
      status: DriverPassStatus.active,
      purchasedAt: now.subtract(const Duration(hours: 2)),
      activatedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.add(const Duration(hours: 1)),
    );
  }

  const policy = DriverEligibilityPolicy();

  test('launchFree approved driver does not require a pass', () {
    final result = policy.evaluate(
      authenticatedUserId: 'user-1',
      profile: profile(),
      pass: null,
      accessMode: DriverAccessMode.launchFree,
      requiredDriverId: 'driver-1',
      now: now,
    );

    expect(result.canUseDriverPlatform, isTrue);
    expect(result.subscriptionActive, isTrue);
    expect(result.rejectionReasons, isEmpty);
  });

  test('paid approved driver without pass is rejected', () {
    final result = policy.evaluate(
      authenticatedUserId: 'user-1',
      profile: profile(),
      pass: null,
      accessMode: DriverAccessMode.paid,
      requiredDriverId: 'driver-1',
      now: now,
    );

    expect(result.canUseDriverPlatform, isFalse);
    expect(result.rejectionReasons, [
      DriverEligibilityRejectionCodes.subscriptionRequired,
    ]);
  });

  test('launchFree does not bypass driver approval', () {
    final result = policy.evaluate(
      authenticatedUserId: 'user-1',
      profile: profile(status: DriverProfileStatus.suspended),
      pass: null,
      accessMode: DriverAccessMode.launchFree,
      requiredDriverId: 'driver-1',
      now: now,
    );

    expect(result.canUseDriverPlatform, isFalse);
    expect(result.rejectionReasons, [
      DriverEligibilityRejectionCodes.driverSuspended,
    ]);
  });

  test('paid keeps existing active-pass behavior', () {
    final result = policy.evaluate(
      authenticatedUserId: 'user-1',
      profile: profile(),
      pass: activePass(),
      accessMode: DriverAccessMode.paid,
      requiredDriverId: 'driver-1',
      now: now,
    );

    expect(result.canUseDriverPlatform, isTrue);
  });

  test('all new-driver gates share launchFree semantics', () {
    final arguments = (
      authenticatedUserId: 'user-1',
      profile: profile(),
      pass: null as DriverAccessPass?,
      requiredDriverId: 'driver-1',
      now: now,
    );

    expect(
      policy.canPublishReturnRoute(
        authenticatedUserId: arguments.authenticatedUserId,
        profile: arguments.profile,
        pass: arguments.pass,
        accessMode: DriverAccessMode.launchFree,
        requiredDriverId: arguments.requiredDriverId,
        now: arguments.now,
      ),
      isTrue,
    );

    expect(
      policy.canReceiveMatches(
        authenticatedUserId: arguments.authenticatedUserId,
        profile: arguments.profile,
        pass: arguments.pass,
        accessMode: DriverAccessMode.launchFree,
        requiredDriverId: arguments.requiredDriverId,
        now: arguments.now,
      ),
      isTrue,
    );

    expect(
      policy.canSendOffer(
        authenticatedUserId: arguments.authenticatedUserId,
        profile: arguments.profile,
        pass: arguments.pass,
        accessMode: DriverAccessMode.launchFree,
        requiredDriverId: arguments.requiredDriverId,
        now: arguments.now,
      ),
      isTrue,
    );
  });

  test('mode parser fails closed unless launchFree is explicit', () {
    expect(
      driverAccessModeFromValue('launchFree'),
      DriverAccessMode.launchFree,
    );

    expect(driverAccessModeFromValue('paid'), DriverAccessMode.paid);

    expect(driverAccessModeFromValue(null), DriverAccessMode.paid);

    expect(driverAccessModeFromValue('other'), DriverAccessMode.paid);
  });
}
