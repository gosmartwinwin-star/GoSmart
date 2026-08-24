enum DriverWorkType {
  vehicleOwner,
  employedDriver,
  shiftDriver;

  String get displayName => switch (this) {
    DriverWorkType.vehicleOwner => 'Araç sahibi',
    DriverWorkType.employedDriver => 'Araç sahibinin yanında çalışan sürücü',
    DriverWorkType.shiftDriver => 'Vardiyalı sürücü',
  };
}
