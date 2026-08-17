import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gosmart_mobile/application/location/location_access_gateway.dart';
import 'package:gosmart_mobile/services/location_access_service.dart';

void main() {
  const validLocation = DeviceLocation(latitude: 41.0082, longitude: 28.9784);

  test('kapali location service ayri state doner', () async {
    var permissionChecks = 0;
    var positionCalls = 0;

    final service = LocationAccessService(
      isServiceEnabled: () async => false,
      checkPermission: () async {
        permissionChecks++;
        return LocationPermission.whileInUse;
      },
      loadPosition: () async {
        positionCalls++;
        return validLocation;
      },
    );

    final result = await service.currentLocation();

    expect(result.granted, isFalse);
    expect(result.issue, LocationAccessIssue.serviceDisabled);
    expect(permissionChecks, 0);
    expect(positionCalls, 0);
  });

  test(
    'denied izin bir kez istenir ve tekrar denied ayri state doner',
    () async {
      var requestCalls = 0;
      var positionCalls = 0;

      final service = LocationAccessService(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async {
          requestCalls++;
          return LocationPermission.denied;
        },
        loadPosition: () async {
          positionCalls++;
          return validLocation;
        },
      );

      final result = await service.currentLocation();

      expect(result.issue, LocationAccessIssue.permissionDenied);
      expect(requestCalls, 1);
      expect(positionCalls, 0);
    },
  );

  test('deniedForever app settings gerektiren state doner', () async {
    var requestCalls = 0;

    final service = LocationAccessService(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.deniedForever,
      requestPermission: () async {
        requestCalls++;
        return LocationPermission.whileInUse;
      },
    );

    final result = await service.currentLocation();

    expect(result.issue, LocationAccessIssue.permissionDeniedForever);
    expect(requestCalls, 0);
  });

  test('whileInUse gecerli konumu granted doner', () async {
    final service = LocationAccessService(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      loadPosition: () async => validLocation,
    );

    final result = await service.currentLocation();

    expect(result.granted, isTrue);
    expect(result.issue, isNull);
    expect(result.location?.latitude, 41.0082);
    expect(result.location?.longitude, 28.9784);
  });

  test('always izni de granted kabul edilir', () async {
    final service = LocationAccessService(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.always,
      loadPosition: () async => validLocation,
    );

    final result = await service.currentLocation();

    expect(result.granted, isTrue);
    expect(result.location, isNotNull);
  });

  test('unableToDetermine fail closed unavailable olur', () async {
    var positionCalls = 0;

    final service = LocationAccessService(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.unableToDetermine,
      loadPosition: () async {
        positionCalls++;
        return validLocation;
      },
    );

    final result = await service.currentLocation();

    expect(result.issue, LocationAccessIssue.unavailable);
    expect(positionCalls, 0);
  });

  test('position exception raw hata sizdirmadan unavailable olur', () async {
    final service = LocationAccessService(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      loadPosition: () async {
        throw StateError('RAW LOCATION PLATFORM DETAIL');
      },
    );

    final result = await service.currentLocation();

    expect(result.granted, isFalse);
    expect(result.issue, LocationAccessIssue.unavailable);

    expect(result.toString(), isNot(contains('RAW LOCATION PLATFORM DETAIL')));
  });

  test('gecersiz coordinate fail closed unavailable olur', () async {
    final service = LocationAccessService(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      loadPosition: () async =>
          const DeviceLocation(latitude: 91, longitude: 28),
    );

    final result = await service.currentLocation();

    expect(result.issue, LocationAccessIssue.unavailable);
  });

  test('settings openers sonucu korunur ve exception false olur', () async {
    final success = LocationAccessService(
      openAppSettings: () async => true,
      openLocationSettings: () async => false,
    );

    expect(await success.openAppSettings(), isTrue);

    expect(await success.openLocationSettings(), isFalse);

    final failure = LocationAccessService(
      openAppSettings: () async {
        throw StateError('raw app settings');
      },
      openLocationSettings: () async {
        throw StateError('raw location settings');
      },
    );

    expect(await failure.openAppSettings(), isFalse);

    expect(await failure.openLocationSettings(), isFalse);
  });
}
