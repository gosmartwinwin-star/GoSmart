enum DriverAccessMode { launchFree, paid }

extension DriverAccessModePolicy on DriverAccessMode {
  bool get requiresPass => this == DriverAccessMode.paid;
}

DriverAccessMode driverAccessModeFromValue(Object? value) {
  return value == 'launchFree'
      ? DriverAccessMode.launchFree
      : DriverAccessMode.paid;
}
