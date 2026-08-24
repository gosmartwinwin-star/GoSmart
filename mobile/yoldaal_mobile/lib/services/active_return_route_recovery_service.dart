import 'package:cloud_functions/cloud_functions.dart';

import '../application/return_route/active_return_route_recovery_gateway.dart';
import '../application/return_route/published_return_route.dart';
import '../core/firebase/firebase_functions_registry.dart';
import '../domain/return_route/driver_return_route.dart';
import '../domain/return_route/driver_return_route_status.dart';
import '../domain/return_route/geo_coordinate.dart';
import '../infrastructure/polyline/geo_polyline_decoder.dart';

class ActiveReturnRouteRecoveryException implements Exception {
  const ActiveReturnRouteRecoveryException(this.code, {this.reason});

  final String code;
  final String? reason;
}

abstract interface class ActiveReturnRouteCallableInvoker {
  Future<Object?> call(String callable, Map<String, dynamic> data);
}

class ActiveReturnRouteRecoveryService
    implements ActiveReturnRouteRecoveryGateway {
  ActiveReturnRouteRecoveryService({ActiveReturnRouteCallableInvoker? invoker})
    : _invoker = invoker ?? _FirebaseActiveReturnRouteCallableInvoker();

  static const _safeCodes = <String>{
    'unauthenticated',
    'permission-denied',
    'failed-precondition',
    'invalid-argument',
    'unavailable',
    'internal',
    'invalid-response',
  };

  static const _safeReasons = <String>{
    'driver_profile_required',
    'duplicate_driver_profile',
    'driver_approval_required',
    'driver_suspended',
    'driver_rejected',
    'driver_deactivated',
    'active_return_route_inconsistent',
    'active_return_route_read_failed',
    'invalid_active_return_route_payload',
  };

  static const _rootKeys = <String>{'activeReturnRoute'};

  static const _routeKeys = <String>{
    'routeId',
    'driverId',
    'status',
    'origin',
    'destination',
    'createdAtMillis',
    'activatedAtMillis',
    'expiresAtMillis',
    'distanceMeters',
    'durationSeconds',
    'encodedPolyline',
  };

  static const _coordinateKeys = <String>{'latitude', 'longitude'};

  final ActiveReturnRouteCallableInvoker _invoker;

  @override
  Future<PublishedReturnRoute?> recover() async {
    Object? rawResponse;

    try {
      rawResponse = await _invoker.call(
        FirebaseFunctionsRegistry.getMyActiveReturnRoute,
        const <String, dynamic>{},
      );
    } on ActiveReturnRouteRecoveryException catch (error) {
      throw ActiveReturnRouteRecoveryException(
        _safeCode(error.code),
        reason: _safeReason(error.reason),
      );
    } catch (_) {
      throw const ActiveReturnRouteRecoveryException('unavailable');
    }

    try {
      if (rawResponse is! Map) {
        throw const FormatException('Invalid recovery response.');
      }

      final response = Map<String, dynamic>.from(rawResponse);

      if (!_hasExactKeys(response, _rootKeys)) {
        throw const FormatException('Invalid recovery response.');
      }

      final rawRoute = response['activeReturnRoute'];

      if (rawRoute == null) {
        return null;
      }

      if (rawRoute is! Map) {
        throw const FormatException('Invalid active return route.');
      }

      final routeMap = Map<String, dynamic>.from(rawRoute);

      if (!_hasExactKeys(routeMap, _routeKeys)) {
        throw const FormatException('Invalid active return route.');
      }

      final routeId = _nonEmptyString(routeMap['routeId']);
      final driverId = _nonEmptyString(routeMap['driverId']);
      final status = routeMap['status'];
      final origin = _coordinate(routeMap['origin']);
      final destination = _coordinate(routeMap['destination']);
      final createdAtMillis = _nonNegativeInteger(routeMap['createdAtMillis']);
      final activatedAtMillis = _nonNegativeInteger(
        routeMap['activatedAtMillis'],
      );
      final expiresAtMillis = _nonNegativeInteger(routeMap['expiresAtMillis']);
      final distanceMeters = _positiveInteger(routeMap['distanceMeters']);
      final durationSeconds = _positiveInteger(routeMap['durationSeconds']);
      final encodedPolyline = _nonEmptyString(routeMap['encodedPolyline']);

      if (routeId == null ||
          driverId == null ||
          status != 'active' ||
          origin == null ||
          destination == null ||
          createdAtMillis == null ||
          activatedAtMillis == null ||
          expiresAtMillis == null ||
          distanceMeters == null ||
          durationSeconds == null ||
          encodedPolyline == null ||
          createdAtMillis > activatedAtMillis ||
          expiresAtMillis <= activatedAtMillis) {
        throw const FormatException('Invalid active return route.');
      }

      final points = GeoPolylineDecoder.decode(encodedPolyline);

      if (points.length < 2) {
        throw const FormatException('Invalid active return route polyline.');
      }

      final createdAt = DateTime.fromMillisecondsSinceEpoch(
        createdAtMillis,
        isUtc: true,
      );

      final activatedAt = DateTime.fromMillisecondsSinceEpoch(
        activatedAtMillis,
        isUtc: true,
      );

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAtMillis,
        isUtc: true,
      );

      final route = DriverReturnRoute(
        id: routeId,
        driverId: driverId,
        origin: origin,
        destination: destination,
        status: DriverReturnRouteStatus.active,
        createdAt: createdAt,
        activatedAt: activatedAt,
        expiresAt: expiresAt,
        routeDistanceMeters: distanceMeters,
        routeDurationSeconds: durationSeconds,
        routePoints: points,
      );

      return PublishedReturnRoute(
        route: route,
        encodedPolyline: encodedPolyline,
      );
    } on ActiveReturnRouteRecoveryException {
      rethrow;
    } catch (_) {
      throw const ActiveReturnRouteRecoveryException('invalid-response');
    }
  }

  static bool _hasExactKeys(Map<String, dynamic> value, Set<String> expected) =>
      value.length == expected.length && value.keys.every(expected.contains);

  static String? _nonEmptyString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }

    return value;
  }

  static int? _nonNegativeInteger(Object? value) {
    if (value is! int || value < 0) {
      return null;
    }

    return value;
  }

  static int? _positiveInteger(Object? value) {
    if (value is! int || value <= 0) {
      return null;
    }

    return value;
  }

  static GeoCoordinate? _coordinate(Object? value) {
    if (value is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(value);

    if (!_hasExactKeys(map, _coordinateKeys)) {
      return null;
    }

    final latitude = map['latitude'];
    final longitude = map['longitude'];

    if (latitude is! num ||
        longitude is! num ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    return GeoCoordinate(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }

  static String _safeCode(String code) =>
      _safeCodes.contains(code) ? code : 'unknown';

  static String? _safeReason(String? reason) =>
      reason != null && _safeReasons.contains(reason) ? reason : null;
}

class _FirebaseActiveReturnRouteCallableInvoker
    implements ActiveReturnRouteCallableInvoker {
  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    try {
      final result = await FirebaseFunctionsRegistry.client
          .httpsCallable(callable)
          .call<Map<String, dynamic>>(data);

      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw ActiveReturnRouteRecoveryException(
        error.code,
        reason: _reasonFromDetails(error.details),
      );
    }
  }

  static String? _reasonFromDetails(Object? details) {
    if (details is! Map) {
      return null;
    }

    final reason = details['reason'];

    return reason is String ? reason : null;
  }
}
