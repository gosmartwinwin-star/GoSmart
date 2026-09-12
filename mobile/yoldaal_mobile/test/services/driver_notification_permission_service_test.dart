import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yoldaal_mobile/services/driver_notification_permission_service.dart';

void main() {
  test('unsupported platform never touches messaging readers', () async {
    var reads = 0;
    var requests = 0;

    final service = DriverNotificationPermissionService(
      supported: false,
      readAuthorizationStatus: () async {
        reads += 1;
        return AuthorizationStatus.notDetermined;
      },
      requestAuthorizationStatus: () async {
        requests += 1;
        return AuthorizationStatus.authorized;
      },
    );

    expect(
      await service.currentStatus(),
      DriverNotificationPermissionState.unsupported,
    );

    expect(
      await service.requestFromUserAction(),
      DriverNotificationPermissionState.unsupported,
    );

    expect(reads, 0);
    expect(requests, 0);
  });

  test('authorized status is read without requesting permission', () async {
    var requests = 0;

    final service = DriverNotificationPermissionService(
      supported: true,
      readAuthorizationStatus: () async => AuthorizationStatus.authorized,
      requestAuthorizationStatus: () async {
        requests += 1;
        return AuthorizationStatus.authorized;
      },
    );

    expect(
      await service.currentStatus(),
      DriverNotificationPermissionState.authorized,
    );

    expect(
      await service.requestFromUserAction(),
      DriverNotificationPermissionState.authorized,
    );

    expect(requests, 0);
  });

  test(
    'not determined permission is requested only from explicit action',
    () async {
      var reads = 0;
      var requests = 0;

      final service = DriverNotificationPermissionService(
        supported: true,
        readAuthorizationStatus: () async {
          reads += 1;
          return AuthorizationStatus.notDetermined;
        },
        requestAuthorizationStatus: () async {
          requests += 1;
          return AuthorizationStatus.authorized;
        },
      );

      expect(
        await service.currentStatus(),
        DriverNotificationPermissionState.notDetermined,
      );

      expect(requests, 0);

      expect(
        await service.requestFromUserAction(),
        DriverNotificationPermissionState.authorized,
      );

      expect(reads, 2);
      expect(requests, 1);
    },
  );

  test('permanent denial is never re-prompted', () async {
    var requests = 0;

    final service = DriverNotificationPermissionService(
      supported: true,
      readAuthorizationStatus: () async =>
          AuthorizationStatus.deniedPermanently,
      requestAuthorizationStatus: () async {
        requests += 1;
        return AuthorizationStatus.authorized;
      },
    );

    expect(
      await service.requestFromUserAction(),
      DriverNotificationPermissionState.deniedPermanently,
    );

    expect(requests, 0);
  });

  test('reader and request failures are fail soft', () async {
    final readFailure = DriverNotificationPermissionService(
      supported: true,
      readAuthorizationStatus: () async => throw StateError('raw-read'),
      requestAuthorizationStatus: () async => AuthorizationStatus.authorized,
    );

    expect(
      await readFailure.currentStatus(),
      DriverNotificationPermissionState.failed,
    );

    final requestFailure = DriverNotificationPermissionService(
      supported: true,
      readAuthorizationStatus: () async => AuthorizationStatus.denied,
      requestAuthorizationStatus: () async => throw StateError('raw-request'),
    );

    expect(
      await requestFailure.requestFromUserAction(),
      DriverNotificationPermissionState.failed,
    );
  });
}
