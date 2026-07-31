import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/driver/driver_eligibility_policy.dart';
import 'package:gosmart_mobile/domain/driver/driver_eligibility_rejection_codes.dart';
import 'package:gosmart_mobile/domain/driver/driver_eligibility_result.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 12);
  const policy = DriverEligibilityPolicy();

  DriverProfile profile({
    String id = 'driver-1',
    String authUserId = 'user-1',
    DriverProfileStatus status = DriverProfileStatus.approved,
    DateTime? createdAt,
    DateTime? approvedAt,
    DateTime? suspendedAt,
  }) => DriverProfile(
    id: id,
    authUserId: authUserId,
    status: status,
    createdAt: createdAt ?? now.subtract(const Duration(days: 2)),
    approvedAt:
        approvedAt ??
        (status == DriverProfileStatus.pendingReview
            ? null
            : now.subtract(const Duration(days: 1))),
    suspendedAt:
        suspendedAt ??
        (status == DriverProfileStatus.suspended
            ? now.subtract(const Duration(hours: 12))
            : null),
  );

  DriverAccessPass pass({String driverId = 'driver-1', DateTime? expiresAt}) =>
      DriverAccessPass(
        id: 'pass-1',
        driverId: driverId,
        plan: DriverPassPlan.daily,
        status: DriverPassStatus.active,
        purchasedAt: now.subtract(const Duration(hours: 2)),
        activatedAt: now.subtract(const Duration(hours: 1)),
        expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
      );

  DriverEligibilityResult evaluate({
    String? userId = 'user-1',
    DriverProfile? driverProfile,
    DriverAccessPass? accessPass,
    String driverId = 'driver-1',
  }) => policy.evaluate(
    authenticatedUserId: userId,
    profile: driverProfile ?? profile(),
    pass: accessPass ?? pass(),
    requiredDriverId: driverId,
    now: now,
  );

  group('DriverProfile', () {
    test('geçerli approved profil oluşturulur', () {
      expect(profile().status, DriverProfileStatus.approved);
    });

    test('boş id reddedilir', () {
      expect(() => profile(id: ' '), throwsArgumentError);
    });

    test('boş authUserId reddedilir', () {
      expect(() => profile(authUserId: ' '), throwsArgumentError);
    });

    test('approved durumda approvedAt eksikse reddedilir', () {
      expect(
        () => DriverProfile(
          id: 'driver-1',
          authUserId: 'user-1',
          status: DriverProfileStatus.approved,
          createdAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('suspended zaman alanları zorunludur', () {
      expect(
        () => DriverProfile(
          id: 'driver-1',
          authUserId: 'user-1',
          status: DriverProfileStatus.suspended,
          createdAt: now,
        ),
        throwsArgumentError,
      );
      expect(
        () => DriverProfile(
          id: 'driver-1',
          authUserId: 'user-1',
          status: DriverProfileStatus.suspended,
          createdAt: now,
          approvedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('approvedAt createdAt öncesinde olamaz', () {
      expect(
        () => profile(
          createdAt: now,
          approvedAt: now.subtract(const Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );
    });

    test('suspendedAt approvedAt öncesinde olamaz', () {
      expect(
        () => profile(
          status: DriverProfileStatus.suspended,
          approvedAt: now,
          suspendedAt: now.subtract(const Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );
    });

    test('yalnızca approved profil isApproved true döndürür', () {
      expect(profile().isApproved, isTrue);
      for (final status in DriverProfileStatus.values.where(
        (value) => value != DriverProfileStatus.approved,
      )) {
        expect(profile(status: status).isApproved, isFalse);
      }
    });
  });

  group('Eligibility', () {
    test('doğru onaylı profil ve aktif pass erişim sağlar', () {
      expect(evaluate().canUseDriverPlatform, isTrue);
    });

    for (final userId in <String?>[null, ' ']) {
      test('geçersiz kullanıcı authentication_required üretir', () {
        expect(evaluate(userId: userId).rejectionReasons, [
          DriverEligibilityRejectionCodes.authenticationRequired,
        ]);
      });
    }

    test('eksik profil driver_profile_required üretir', () {
      final result = policy.evaluate(
        authenticatedUserId: 'user-1',
        profile: null,
        pass: pass(),
        requiredDriverId: 'driver-1',
        now: now,
      );
      expect(result.rejectionReasons, [
        DriverEligibilityRejectionCodes.driverProfileRequired,
      ]);
    });

    test(
      'profil kullanıcı kimliği uyuşmazlığında yalnızca kimlik kodu döner',
      () {
        expect(
          evaluate(
            driverProfile: profile(authUserId: 'other'),
          ).rejectionReasons,
          [DriverEligibilityRejectionCodes.driverIdentityMismatch],
        );
      },
    );

    test('profil sürücü kimliği uyuşmazlığında yalnızca kimlik kodu döner', () {
      expect(evaluate(driverId: 'other').rejectionReasons, [
        DriverEligibilityRejectionCodes.driverIdentityMismatch,
      ]);
    });

    test('pass sürücü kimliği uyuşmazlığında yalnızca kimlik kodu döner', () {
      expect(evaluate(accessPass: pass(driverId: 'other')).rejectionReasons, [
        DriverEligibilityRejectionCodes.driverIdentityMismatch,
      ]);
    });

    final statusReasons = {
      DriverProfileStatus.pendingReview:
          DriverEligibilityRejectionCodes.driverApprovalRequired,
      DriverProfileStatus.suspended:
          DriverEligibilityRejectionCodes.driverSuspended,
      DriverProfileStatus.rejected:
          DriverEligibilityRejectionCodes.driverRejected,
      DriverProfileStatus.deactivated:
          DriverEligibilityRejectionCodes.driverDeactivated,
    };
    for (final entry in statusReasons.entries) {
      test('${entry.key} doğru ret nedenini üretir', () {
        expect(
          evaluate(driverProfile: profile(status: entry.key)).rejectionReasons,
          [entry.value],
        );
      });
    }

    test('approved profil ve null pass subscription_required üretir', () {
      final result = policy.evaluate(
        authenticatedUserId: 'user-1',
        profile: profile(),
        pass: null,
        requiredDriverId: 'driver-1',
        now: now,
      );
      expect(result.rejectionReasons, [
        DriverEligibilityRejectionCodes.subscriptionRequired,
      ]);
    });

    test('expired pass subscription_required üretir', () {
      expect(evaluate(accessPass: pass(expiresAt: now)).rejectionReasons, [
        DriverEligibilityRejectionCodes.subscriptionRequired,
      ]);
    });

    test('üç sürücü işlemi aynı merkezi uygunluğu kullanır', () {
      final arguments = (
        authenticatedUserId: 'user-1',
        profile: profile(),
        pass: pass(),
        requiredDriverId: 'driver-1',
        now: now,
      );
      expect(
        policy.canPublishReturnRoute(
          authenticatedUserId: arguments.authenticatedUserId,
          profile: arguments.profile,
          pass: arguments.pass,
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
          requiredDriverId: arguments.requiredDriverId,
          now: arguments.now,
        ),
        isTrue,
      );
      expect(
        policy.canSendOffer(
          authenticatedUserId: 'user-1',
          profile: profile(status: DriverProfileStatus.pendingReview),
          pass: pass(),
          requiredDriverId: 'driver-1',
          now: now,
        ),
        isFalse,
      );
    });

    test('rejectionReasons immutable, benzersiz ve sıralıdır', () {
      final result = DriverEligibilityResult(
        authenticated: false,
        driverProfilePresent: false,
        identityCompatible: false,
        driverApproved: false,
        subscriptionActive: false,
        rejectionReasons: const ['a', 'b', 'a'],
      );
      expect(result.rejectionReasons, ['a', 'b']);
      expect(() => result.rejectionReasons.add('c'), throwsUnsupportedError);
    });

    test('başka kullanıcı suspended profilinin durumunu sızdırmaz', () {
      expect(
        evaluate(
          driverProfile: profile(
            authUserId: 'other',
            status: DriverProfileStatus.suspended,
          ),
        ).rejectionReasons,
        [DriverEligibilityRejectionCodes.driverIdentityMismatch],
      );
    });

    test('kimlik uyuşmazlığında expired abonelik durumu sızdırılmaz', () {
      expect(
        evaluate(
          driverProfile: profile(authUserId: 'other'),
          accessPass: pass(expiresAt: now),
        ).rejectionReasons,
        [DriverEligibilityRejectionCodes.driverIdentityMismatch],
      );
    });
  });
}
