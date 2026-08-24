import '../../domain/subscription/driver_access_mode.dart';

abstract interface class DriverAccessModeRepository {
  Future<DriverAccessMode> load();
}

class PaidDriverAccessModeRepository implements DriverAccessModeRepository {
  const PaidDriverAccessModeRepository();

  @override
  Future<DriverAccessMode> load() async => DriverAccessMode.paid;
}
