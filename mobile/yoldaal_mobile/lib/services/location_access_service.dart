import 'package:geolocator/geolocator.dart';

import '../application/location/location_access_gateway.dart';

typedef LocationServiceEnabledReader = Future<bool> Function();

typedef LocationPermissionReader = Future<LocationPermission> Function();

typedef DeviceLocationLoader = Future<DeviceLocation> Function();

typedef LocationSettingsOpener = Future<bool> Function();

class LocationAccessService implements LocationAccessGateway {
  LocationAccessService({
    LocationServiceEnabledReader? isServiceEnabled,
    LocationPermissionReader? checkPermission,
    LocationPermissionReader? requestPermission,
    DeviceLocationLoader? loadPosition,
    LocationSettingsOpener? openAppSettings,
    LocationSettingsOpener? openLocationSettings,
  }) : _isServiceEnabled =
           isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _loadPosition = loadPosition ?? _defaultLoadPosition,
       _openAppSettings = openAppSettings ?? Geolocator.openAppSettings,
       _openLocationSettings =
           openLocationSettings ?? Geolocator.openLocationSettings;

  final LocationServiceEnabledReader _isServiceEnabled;

  final LocationPermissionReader _checkPermission;

  final LocationPermissionReader _requestPermission;

  final DeviceLocationLoader _loadPosition;

  final LocationSettingsOpener _openAppSettings;

  final LocationSettingsOpener _openLocationSettings;

  @override
  Future<LocationAccessResult> currentLocation() async {
    try {
      final serviceEnabled = await _isServiceEnabled();

      if (!serviceEnabled) {
        return const LocationAccessResult.failed(
          LocationAccessIssue.serviceDisabled,
        );
      }

      var permission = await _checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await _requestPermission();
      }

      switch (permission) {
        case LocationPermission.denied:
          return const LocationAccessResult.failed(
            LocationAccessIssue.permissionDenied,
          );

        case LocationPermission.deniedForever:
          return const LocationAccessResult.failed(
            LocationAccessIssue.permissionDeniedForever,
          );

        case LocationPermission.unableToDetermine:
          return const LocationAccessResult.failed(
            LocationAccessIssue.unavailable,
          );

        case LocationPermission.whileInUse:
        case LocationPermission.always:
          final location = await _loadPosition();

          if (!location.isValid) {
            return const LocationAccessResult.failed(
              LocationAccessIssue.unavailable,
            );
          }

          return LocationAccessResult.granted(location);
      }
    } catch (_) {
      return const LocationAccessResult.failed(LocationAccessIssue.unavailable);
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await _openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await _openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  static Future<DeviceLocation> _defaultLoadPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );

    return DeviceLocation(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
