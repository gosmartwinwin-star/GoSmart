import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

enum DriverNotificationPermissionState {
  unsupported,
  notDetermined,
  denied,
  deniedPermanently,
  authorized,
  failed,
}

abstract interface class DriverNotificationPermissionGateway {
  Future<DriverNotificationPermissionState> currentStatus();

  Future<DriverNotificationPermissionState> requestFromUserAction();
}

typedef DriverNotificationAuthorizationReader =
    Future<AuthorizationStatus> Function();

class DriverNotificationPermissionService
    implements DriverNotificationPermissionGateway {
  DriverNotificationPermissionService({
    bool? supported,
    DriverNotificationAuthorizationReader? readAuthorizationStatus,
    DriverNotificationAuthorizationReader? requestAuthorizationStatus,
  }) : _supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       _readAuthorizationStatus =
           readAuthorizationStatus ?? _defaultReadAuthorizationStatus,
       _requestAuthorizationStatus =
           requestAuthorizationStatus ?? _defaultRequestAuthorizationStatus;

  final bool _supported;
  final DriverNotificationAuthorizationReader _readAuthorizationStatus;
  final DriverNotificationAuthorizationReader _requestAuthorizationStatus;

  @override
  Future<DriverNotificationPermissionState> currentStatus() async {
    if (!_supported) {
      return DriverNotificationPermissionState.unsupported;
    }

    try {
      return _mapAuthorizationStatus(await _readAuthorizationStatus());
    } catch (_) {
      return DriverNotificationPermissionState.failed;
    }
  }

  @override
  Future<DriverNotificationPermissionState> requestFromUserAction() async {
    if (!_supported) {
      return DriverNotificationPermissionState.unsupported;
    }

    try {
      final current = _mapAuthorizationStatus(await _readAuthorizationStatus());

      if (current == DriverNotificationPermissionState.authorized ||
          current == DriverNotificationPermissionState.deniedPermanently) {
        return current;
      }

      return _mapAuthorizationStatus(await _requestAuthorizationStatus());
    } catch (_) {
      return DriverNotificationPermissionState.failed;
    }
  }

  static Future<AuthorizationStatus> _defaultReadAuthorizationStatus() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();

    return settings.authorizationStatus;
  }

  static Future<AuthorizationStatus>
  _defaultRequestAuthorizationStatus() async {
    final settings = await FirebaseMessaging.instance.requestPermission();

    return settings.authorizationStatus;
  }

  static DriverNotificationPermissionState _mapAuthorizationStatus(
    AuthorizationStatus status,
  ) {
    return switch (status) {
      AuthorizationStatus.authorized =>
        DriverNotificationPermissionState.authorized,
      AuthorizationStatus.provisional =>
        DriverNotificationPermissionState.authorized,
      AuthorizationStatus.notDetermined =>
        DriverNotificationPermissionState.notDetermined,
      AuthorizationStatus.denied => DriverNotificationPermissionState.denied,
      AuthorizationStatus.deniedPermanently =>
        DriverNotificationPermissionState.deniedPermanently,
    };
  }
}
