import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final screen = File(
    'lib/screens/driver/driver_center_screen.dart',
  ).readAsStringSync();

  final service = File(
    'lib/services/driver_notification_permission_service.dart',
  ).readAsStringSync();

  final main = File('lib/main.dart').readAsStringSync();

  test('driver center injects Android-only permission gateway', () {
    expect(
      screen,
      contains(
        'final DriverNotificationPermissionGateway? '
        'notificationPermissionGateway;',
      ),
    );

    expect(screen, contains('this.notificationPermissionGateway,'));

    expect(screen, contains('defaultTargetPlatform != TargetPlatform.android'));

    expect(screen, contains('_initializeDriverNotificationPermission();'));
  });

  test(
    'notification prompt is reachable only through explicit driver action',
    () {
      expect(
        screen,
        contains("const ValueKey('driver-notification-permission-action')"),
      );

      expect(
        screen,
        contains('unawaited(_requestDriverNotificationPermission());'),
      );

      expect(
        RegExp(
          r'_requestDriverNotificationPermission\(\)',
        ).allMatches(screen).length,
        2,
      );

      expect(screen, contains('controller.status == DriverCenterStatus.ready'));

      expect(
        service,
        contains('FirebaseMessaging.instance.requestPermission()'),
      );
    },
  );

  test('permission foundation adds no token or bootstrap authority', () {
    final combined = '$screen\n$service\n$main';

    expect(RegExp(r'\bgetToken\s*\(').hasMatch(combined), isFalse);

    expect(RegExp(r'\bgetAPNSToken\s*\(').hasMatch(combined), isFalse);

    expect(RegExp(r'\bsetAutoInitEnabled\s*\(').hasMatch(combined), isFalse);

    expect(main.contains('requestPermission'), isFalse);
  });
}
