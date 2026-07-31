import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_context_service.dart';
import 'package:gosmart_mobile/application/driver_access/driver_access_pass_repository.dart';
import 'package:gosmart_mobile/application/driver_access/driver_profile_repository.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 12);

  DriverProfile profile({
    String id = 'driver-1',
    DriverProfileStatus status = DriverProfileStatus.approved,
  }) => DriverProfile(
    id: id,
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

  Future<
    ({dynamic context, _ProfileRepository profiles, _PassRepository passes})
  >
  load({
    String? userId = 'user-1',
    DriverProfile? loadedProfile,
    DriverAccessPass? loadedPass,
    Object? profileError,
    Object? passError,
    String requiredDriverId = 'driver-1',
  }) async {
    final profiles = _ProfileRepository(loadedProfile, profileError);
    final passes = _PassRepository(loadedPass, passError);
    final context =
        await DriverAccessContextService(
          profileRepository: profiles,
          passRepository: passes,
        ).load(
          authenticatedUserId: userId,
          requiredDriverId: requiredDriverId,
          now: now,
        );
    return (context: context, profiles: profiles, passes: passes);
  }

  for (final userId in <String?>[null, ' ']) {
    test('geçersiz auth repository çağırmadan reddedilir', () async {
      final result = await load(userId: userId);
      expect(result.context.eligibility.rejectionReasons, [
        'authentication_required',
      ]);
      expect(result.profiles.calls, 0);
      expect(result.passes.calls, 0);
    });
  }

  test('profil yoksa pass yüklenmez', () async {
    final result = await load();
    expect(result.context.eligibility.rejectionReasons, [
      'driver_profile_required',
    ]);
    expect(result.profiles.calls, 1);
    expect(result.passes.calls, 0);
  });

  test('approved profil ve aktif pass erişim sağlar', () async {
    final result = await load(loadedProfile: profile(), loadedPass: pass());
    expect(result.context.canUseDriverPlatform, isTrue);
  });

  final statusReasons = {
    DriverProfileStatus.pendingReview: 'driver_approval_required',
    DriverProfileStatus.suspended: 'driver_suspended',
    DriverProfileStatus.rejected: 'driver_rejected',
    DriverProfileStatus.deactivated: 'driver_deactivated',
  };
  for (final entry in statusReasons.entries) {
    test('${entry.key} profil doğru nedenle reddedilir', () async {
      final result = await load(
        loadedProfile: profile(status: entry.key),
        loadedPass: pass(),
      );
      expect(result.context.eligibility.rejectionReasons, [entry.value]);
    });
  }

  test('approved profil ve eksik pass subscription_required üretir', () async {
    final result = await load(loadedProfile: profile());
    expect(result.context.eligibility.rejectionReasons, [
      'subscription_required',
    ]);
  });

  test(
    'expiresAt anındaki pass aktif değildir ve verilen now kullanılır',
    () async {
      final result = await load(
        loadedProfile: profile(),
        loadedPass: pass(expiresAt: now),
      );
      expect(result.context.eligibility.rejectionReasons, [
        'subscription_required',
      ]);
    },
  );

  test(
    'profil ve pass kimlik uyuşmazlıkları yalnızca kimlik kodu üretir',
    () async {
      final profileMismatch = await load(
        loadedProfile: profile(),
        loadedPass: pass(),
        requiredDriverId: 'other',
      );
      expect(profileMismatch.context.eligibility.rejectionReasons, [
        'driver_identity_mismatch',
      ]);
      final passMismatch = await load(
        loadedProfile: profile(),
        loadedPass: pass(driverId: 'other'),
      );
      expect(passMismatch.context.eligibility.rejectionReasons, [
        'driver_identity_mismatch',
      ]);
    },
  );

  test('repository hataları aynen aktarılır', () async {
    final first = StateError('profile failure');
    await expectLater(load(profileError: first), throwsA(same(first)));
    final second = StateError('pass failure');
    await expectLater(
      load(loadedProfile: profile(), passError: second),
      throwsA(same(second)),
    );
  });

  test('boş requiredDriverId reddedilir ve repository çağrılmaz', () async {
    await expectLater(load(requiredDriverId: ' '), throwsArgumentError);
  });
}

class _ProfileRepository implements DriverProfileRepository {
  final DriverProfile? value;
  final Object? error;
  int calls = 0;
  _ProfileRepository(this.value, this.error);
  @override
  Future<DriverProfile?> findByAuthenticatedUserId(
    String authenticatedUserId,
  ) async {
    calls++;
    if (error != null) throw error!;
    return value;
  }
}

class _PassRepository implements DriverAccessPassRepository {
  final DriverAccessPass? value;
  final Object? error;
  int calls = 0;
  _PassRepository(this.value, this.error);
  @override
  Future<DriverAccessPass?> findLatestForDriver(String driverId) async {
    calls++;
    if (error != null) throw error!;
    return value;
  }
}
