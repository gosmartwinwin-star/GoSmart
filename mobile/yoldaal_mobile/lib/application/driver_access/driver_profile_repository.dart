import '../../domain/driver/driver_profile.dart';

abstract interface class DriverProfileRepository {
  Future<DriverProfile?> findByAuthenticatedUserId(String authenticatedUserId);
}
