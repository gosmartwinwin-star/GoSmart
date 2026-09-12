import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../application/location/location_access_gateway.dart';

typedef LocationServiceEnabledReader = Future<bool> Function();

typedef LocationPermissionReader = Future<LocationPermission> Function();

typedef DeviceLocationLoader = Future<DeviceLocation> Function();
typedef DeviceLocationStreamLoader = Stream<DeviceLocation> Function();

typedef LocationSettingsOpener = Future<bool> Function();

class LocationAccessService implements LocationAccessGateway {
  LocationAccessService({
    LocationServiceEnabledReader? isServiceEnabled,
    LocationPermissionReader? checkPermission,
    LocationPermissionReader? requestPermission,
    DeviceLocationLoader? loadPosition,
    DeviceLocationStreamLoader? loadPositionStream,
    LocationSettingsOpener? openAppSettings,
    LocationSettingsOpener? openLocationSettings,
  }) : _isServiceEnabled =
           isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _loadPosition = loadPosition ?? _defaultLoadPosition,
       _loadPositionStream =
           loadPositionStream ?? _defaultLoadPositionStream,
       _openAppSettings = openAppSettings ?? Geolocator.openAppSettings,
       _openLocationSettings =
           openLocationSettings ?? Geolocator.openLocationSettings;

  final LocationServiceEnabledReader _isServiceEnabled;

  final LocationPermissionReader _checkPermission;

  final LocationPermissionReader _requestPermission;

  final DeviceLocationLoader _loadPosition;

  final DeviceLocationStreamLoader _loadPositionStream;

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

  Stream<DeviceLocation> locationStream() => _loadPositionStream();

  static Stream<DeviceLocation> _defaultLoadPositionStream() {
    final LocationSettings settings;

    if (
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android
    ) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig:
            const ForegroundNotificationConfig(
              notificationTitle: 'YoldaAl aktif yolculuk',
              notificationText:
                  'Aktif yolculuk sırasında konumunuz paylaşılıyor.',
              notificationChannelName: 'YoldaAl yolculuk konumu',
              setOngoing: true,
            ),
      );
    } else if (
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS
    ) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );
    }

    return Geolocator.getPositionStream(
      locationSettings: settings,
    )
        .map(
          (position) => DeviceLocation(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
        )
        .where((location) => location.isValid);
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
