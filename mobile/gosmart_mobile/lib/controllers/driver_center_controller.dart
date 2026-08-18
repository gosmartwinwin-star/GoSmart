import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/location/location_access_gateway.dart';
import '../application/driver_access/driver_access_mode_repository.dart';
import '../application/driver_access/driver_access_pass_repository.dart';
import '../application/driver_access/driver_profile_repository.dart';
import '../application/return_route/publish_return_route_gateway.dart';
import '../application/return_route/active_return_route_recovery_gateway.dart';
import '../application/return_route/published_return_route.dart';
import '../application/driver_application/driver_application_repository.dart';
import '../domain/driver_application/driver_application_review.dart';
import '../domain/driver/driver_eligibility_policy.dart';
import '../domain/driver/driver_eligibility_result.dart';
import '../domain/subscription/driver_access_mode.dart';
import '../domain/return_route/geo_coordinate.dart';
import '../services/publish_return_route_service.dart';

enum DriverCenterStatus { loading, restricted, ready, error }

abstract interface class DriverCenterAuthGateway {
  String? get authenticatedUserId;
}

class DriverCenterController extends ChangeNotifier {
  final DriverCenterAuthGateway _auth;
  final DriverProfileRepository _profiles;
  final DriverAccessPassRepository _passes;
  final DriverAccessModeRepository _accessModes;
  final PublishReturnRouteGateway _publisher;
  final ActiveReturnRouteRecoveryGateway? _returnRouteRecovery;
  final Timer Function(Duration, void Function()) _expiryTimerFactory;
  Timer? _publishedRouteExpiryTimer;
  final LocationAccessGateway _location;
  final DriverEligibilityPolicy _eligibilityPolicy;
  final DateTime Function() _now;
  final DriverApplicationRepository? _applications;

  DriverCenterStatus status = DriverCenterStatus.loading;
  DriverEligibilityResult? eligibility;
  DriverAccessMode accessMode = DriverAccessMode.paid;
  GeoCoordinate? origin;
  GeoCoordinate? destination;
  String? destinationLabel;
  int validForSeconds = 3600;
  PublishedReturnRoute? publishedRoute;
  String? errorMessage;
  LocationAccessIssue? locationIssue;
  bool locationLoading = false;
  bool publishing = false;
  bool _disposed = false;
  DriverApplicationReview? application;
  bool applicationLoadFailed = false;

  DriverCenterController({
    required DriverCenterAuthGateway auth,
    required DriverProfileRepository profiles,
    required DriverAccessPassRepository passes,
    DriverAccessModeRepository accessModes =
        const PaidDriverAccessModeRepository(),
    required PublishReturnRouteGateway publisher,
    ActiveReturnRouteRecoveryGateway? returnRouteRecovery,
    Timer Function(Duration, void Function())? expiryTimerFactory,
    required LocationAccessGateway location,
    DriverEligibilityPolicy eligibilityPolicy = const DriverEligibilityPolicy(),
    DateTime Function()? now,
    DriverApplicationRepository? applications,
  }) : _auth = auth,
       _profiles = profiles,
       _passes = passes,
       _accessModes = accessModes,
       _publisher = publisher,
       _returnRouteRecovery = returnRouteRecovery,
       _expiryTimerFactory =
           expiryTimerFactory ?? ((delay, callback) => Timer(delay, callback)),
       _location = location,
       _eligibilityPolicy = eligibilityPolicy,
       _applications = applications,
       _now = now ?? DateTime.now;

  bool get canPublish =>
      status == DriverCenterStatus.ready &&
      !publishing &&
      origin != null &&
      destination != null &&
      origin != destination &&
      validForSeconds >= 900 &&
      validForSeconds <= 14400;

  String? get rejectionReason => eligibility?.rejectionReasons.firstOrNull;

  Future<void> load() async {
    status = DriverCenterStatus.loading;
    errorMessage = null;
    accessMode = DriverAccessMode.paid;
    _cancelPublishedRouteExpiryTimer();
    if (_returnRouteRecovery != null) {
      publishedRoute = null;
    }
    _notify();
    final userId = _auth.authenticatedUserId;
    if (userId?.trim().isNotEmpty != true) {
      eligibility = _eligibilityPolicy.evaluate(
        authenticatedUserId: userId,
        profile: null,
        pass: null,
        requiredDriverId: 'unavailable',
        now: _now(),
      );
      status = DriverCenterStatus.restricted;
      _notify();
      return;
    }
    try {
      final profile = await _profiles.findByAuthenticatedUserId(userId!);
      if (profile == null && _applications != null) {
        try {
          application = await _applications.findForAuthenticatedUser();
          applicationLoadFailed = false;
        } catch (_) {
          application = null;
          applicationLoadFailed = true;
        }
      } else {
        application = null;
        applicationLoadFailed = false;
      }
      if (profile != null) {
        accessMode = await _loadAccessModeFailClosed();
      }

      final pass = profile == null || !accessMode.requiresPass
          ? null
          : await _passes.findLatestForDriver(profile.id);
      eligibility = _eligibilityPolicy.evaluate(
        authenticatedUserId: userId,
        profile: profile,
        pass: pass,
        accessMode: accessMode,
        requiredDriverId: profile?.id ?? 'unavailable',
        now: _now(),
      );
      status = eligibility!.canUseDriverPlatform
          ? DriverCenterStatus.ready
          : DriverCenterStatus.restricted;

      if (status == DriverCenterStatus.ready && _returnRouteRecovery != null) {
        try {
          publishedRoute = await _returnRouteRecovery.recover();
          _schedulePublishedRouteExpiry();
        } catch (_) {
          status = DriverCenterStatus.error;
          errorMessage =
              'Aktif dönüş rotası yüklenemedi. Lütfen tekrar deneyin.';
          _notify();
          return;
        }
      }

      _notify();

      if (status == DriverCenterStatus.ready) {
        await loadLocation();
      }
    } catch (_) {
      status = DriverCenterStatus.error;
      errorMessage = 'Bilgiler yüklenemedi';
      _notify();
    }
  }

  Future<DriverAccessMode> _loadAccessModeFailClosed() async {
    try {
      return await _accessModes.load();
    } catch (_) {
      return DriverAccessMode.paid;
    }
  }

  Future<void> loadLocation() async {
    if (locationLoading) return;

    locationLoading = true;
    locationIssue = null;
    errorMessage = null;
    _notify();

    try {
      final result = await _location.currentLocation();

      final location = result.location;

      if (!result.granted || location == null) {
        origin = null;
        locationIssue = result.issue ?? LocationAccessIssue.unavailable;
        return;
      }

      origin = GeoCoordinate(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      locationIssue = null;
    } catch (_) {
      origin = null;
      locationIssue = LocationAccessIssue.unavailable;
    } finally {
      locationLoading = false;
      _notify();
    }
  }

  Future<void> handleLocationIssueAction() async {
    final issue = locationIssue;

    if (issue == null || locationLoading) {
      return;
    }

    try {
      switch (issue) {
        case LocationAccessIssue.serviceDisabled:
          await _location.openLocationSettings();
          return;

        case LocationAccessIssue.permissionDeniedForever:
          await _location.openAppSettings();
          return;

        case LocationAccessIssue.permissionDenied:
        case LocationAccessIssue.unavailable:
          await loadLocation();
          return;
      }
    } catch (_) {
      // Settings failures remain fail-closed.
    }
  }

  void selectDestination(GeoCoordinate value, String label) {
    destination = value;
    destinationLabel = label;
    _notify();
  }

  void selectValidity(int seconds) {
    if ({900, 1800, 3600, 7200, 14400}.contains(seconds)) {
      validForSeconds = seconds;
      _notify();
    }
  }

  Future<void> publish() async {
    if (!canPublish) return;
    publishing = true;
    errorMessage = null;
    _notify();
    try {
      publishedRoute = await _publisher.publish(
        origin: origin!,
        destination: destination!,
        validForSeconds: validForSeconds,
      );
      _schedulePublishedRouteExpiry();
    } on PublishReturnRouteException catch (error) {
      errorMessage = messageForPublishReason(error.reason);
    } catch (_) {
      errorMessage = messageForPublishReason(null);
    } finally {
      publishing = false;
      _notify();
    }
  }

  static String messageForPublishReason(String? reason) => switch (reason) {
    'driver_profile_required' => 'Sürücü profiliniz bulunamadı.',
    'duplicate_driver_profile' =>
      'Sürücü profiliniz doğrulanamadı. Destek ile iletişime geçin.',
    'driver_approval_required' => 'Sürücü profiliniz henüz onaylanmadı.',
    'driver_suspended' => 'Sürücü erişiminiz askıya alınmış.',
    'driver_rejected' => 'Sürücü başvurunuz onaylanmadı.',
    'driver_deactivated' => 'Sürücü profiliniz devre dışı.',
    'subscription_required' => 'Aktif GoSmart kontör paketiniz bulunmuyor.',
    'active_return_route_exists' => 'Zaten aktif bir dönüş rotanız bulunuyor.',
    'invalid_route_coordinates' => 'Başlangıç veya hedef konumu geçerli değil.',
    'invalid_route_validity' => 'Dönüş rotası süresi geçerli değil.',
    'route_computation_failed' => 'Dönüş rotası şu anda hesaplanamadı.',
    'route_persistence_failed' => 'Dönüş rotası kaydedilemedi.',
    _ => 'İşlem şu anda tamamlanamadı. Lütfen tekrar deneyin.',
  };

  void _cancelPublishedRouteExpiryTimer() {
    _publishedRouteExpiryTimer?.cancel();
    _publishedRouteExpiryTimer = null;
  }

  void _schedulePublishedRouteExpiry() {
    _cancelPublishedRouteExpiryTimer();

    if (_disposed) {
      return;
    }

    final scheduledRoute = publishedRoute;

    if (scheduledRoute == null) {
      return;
    }

    final remaining = scheduledRoute.expiresAt.difference(_now());

    if (remaining <= Duration.zero) {
      publishedRoute = null;
      _notify();
      return;
    }

    _publishedRouteExpiryTimer = _expiryTimerFactory(remaining, () {
      _publishedRouteExpiryTimer = null;

      if (_disposed) {
        return;
      }

      final currentRoute = publishedRoute;

      if (currentRoute == null ||
          currentRoute.routeId != scheduledRoute.routeId ||
          currentRoute.expiresAt != scheduledRoute.expiresAt) {
        return;
      }

      if (_now().isBefore(currentRoute.expiresAt)) {
        _schedulePublishedRouteExpiry();
        return;
      }

      publishedRoute = null;
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _cancelPublishedRouteExpiryTimer();
    _disposed = true;
    super.dispose();
  }
}
