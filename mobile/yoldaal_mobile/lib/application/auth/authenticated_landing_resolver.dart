import '../driver_access/driver_profile_repository.dart';

enum AuthenticatedLanding { passenger, driver }

class AuthenticatedLandingResolver {
  const AuthenticatedLandingResolver({required this.profiles});

  final DriverProfileRepository profiles;

  Future<AuthenticatedLanding> resolve(String authenticatedUserId) async {
    if (authenticatedUserId.trim().isEmpty) {
      throw ArgumentError.value(
        authenticatedUserId,
        'authenticatedUserId',
        'Cannot be empty.',
      );
    }

    final profile = await profiles.findByAuthenticatedUserId(
      authenticatedUserId,
    );

    return profile?.isApproved == true
        ? AuthenticatedLanding.driver
        : AuthenticatedLanding.passenger;
  }
}
