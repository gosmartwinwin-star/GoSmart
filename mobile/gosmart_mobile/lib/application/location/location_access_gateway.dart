enum LocationAccessIssue {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class DeviceLocation {
  const DeviceLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

class LocationAccessResult {
  const LocationAccessResult.granted(DeviceLocation value)
    : location = value,
      issue = null;

  const LocationAccessResult.failed(LocationAccessIssue value)
    : location = null,
      issue = value;

  final DeviceLocation? location;
  final LocationAccessIssue? issue;

  bool get granted => location != null && issue == null;
}

abstract interface class LocationAccessGateway {
  Future<LocationAccessResult> currentLocation();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}
