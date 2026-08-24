import '../../domain/subscription/driver_access_pass.dart';

abstract interface class DriverAccessPassRepository {
  Future<DriverAccessPass?> findLatestForDriver(String driverId);
}
