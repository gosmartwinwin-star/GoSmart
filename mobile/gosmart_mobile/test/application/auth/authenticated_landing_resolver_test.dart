import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/auth/authenticated_landing_resolver.dart';
import 'package:gosmart_mobile/application/driver_access/driver_profile_repository.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';

void main() {
  final now = DateTime.utc(2026, 8, 14, 12);

  DriverProfile profile(DriverProfileStatus status) => DriverProfile(
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

  test('approved profile resolves driver landing', () async {
    final repository = _Profiles(profile(DriverProfileStatus.approved));
    final resolver = AuthenticatedLandingResolver(profiles: repository);

    expect(await resolver.resolve('user-1'), AuthenticatedLanding.driver);
    expect(repository.requestedIds, ['user-1']);
  });

  test('missing profile resolves passenger landing', () async {
    final resolver = AuthenticatedLandingResolver(profiles: _Profiles(null));

    expect(await resolver.resolve('user-1'), AuthenticatedLanding.passenger);
  });

  for (final status in DriverProfileStatus.values.where(
    (value) => value != DriverProfileStatus.approved,
  )) {
    test('$status profile resolves passenger landing', () async {
      final resolver = AuthenticatedLandingResolver(
        profiles: _Profiles(profile(status)),
      );

      expect(await resolver.resolve('user-1'), AuthenticatedLanding.passenger);
    });
  }

  test('repository failure is not hidden as passenger role', () async {
    final error = StateError('repository failure');
    final resolver = AuthenticatedLandingResolver(
      profiles: _Profiles(null, error: error),
    );

    await expectLater(resolver.resolve('user-1'), throwsA(same(error)));
  });

  test('blank uid is rejected before repository call', () async {
    final repository = _Profiles(null);
    final resolver = AuthenticatedLandingResolver(profiles: repository);

    await expectLater(resolver.resolve('   '), throwsArgumentError);
    expect(repository.requestedIds, isEmpty);
  });
}

class _Profiles implements DriverProfileRepository {
  _Profiles(this.value, {this.error});

  final DriverProfile? value;
  final Object? error;
  final List<String> requestedIds = [];

  @override
  Future<DriverProfile?> findByAuthenticatedUserId(
    String authenticatedUserId,
  ) async {
    requestedIds.add(authenticatedUserId);
    if (error case final value?) throw value;
    return value;
  }
}
