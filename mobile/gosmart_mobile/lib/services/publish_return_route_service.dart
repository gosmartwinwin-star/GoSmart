import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../application/return_route/publish_return_route_gateway.dart';
import '../application/return_route/published_return_route.dart';
import '../domain/return_route/driver_return_route.dart';
import '../domain/return_route/driver_return_route_status.dart';
import '../domain/return_route/geo_coordinate.dart';
import '../infrastructure/polyline/geo_polyline_decoder.dart';

class PublishReturnRouteException implements Exception {
  final String code;
  final String? reason;

  const PublishReturnRouteException({required this.code, this.reason});
}

abstract interface class PublishReturnRouteAuthSession {
  Future<void> requireAuthenticatedUser();
}

abstract interface class PublishReturnRouteCallableInvoker {
  Future<Object?> call(Map<String, Object?> payload);
}

class FirebasePublishReturnRouteAuthSession
    implements PublishReturnRouteAuthSession {
  final FirebaseAuth _auth;

  FirebasePublishReturnRouteAuthSession({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  @override
  Future<void> requireAuthenticatedUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const PublishReturnRouteException(code: 'unauthenticated');
    }
    try {
      await user.getIdToken(true);
    } on FirebaseAuthException {
      throw const PublishReturnRouteException(code: 'unauthenticated');
    }
  }
}

class FirebasePublishReturnRouteCallableInvoker
    implements PublishReturnRouteCallableInvoker {
  final FirebaseFunctions _functions;

  FirebasePublishReturnRouteCallableInvoker({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(
            app: Firebase.app(),
            region: 'europe-west1',
          );

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final callable = _functions.httpsCallable(
        'publishReturnRoute',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
      );
      final result = await callable.call<Map<String, Object?>>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map && details['reason'] is String
          ? details['reason'] as String
          : null;
      throw PublishReturnRouteException(code: error.code, reason: reason);
    }
  }
}

class PublishReturnRouteService implements PublishReturnRouteGateway {
  final PublishReturnRouteAuthSession _authSession;
  final PublishReturnRouteCallableInvoker _invoker;

  PublishReturnRouteService({
    PublishReturnRouteAuthSession? authSession,
    PublishReturnRouteCallableInvoker? invoker,
  }) : _authSession = authSession ?? FirebasePublishReturnRouteAuthSession(),
       _invoker = invoker ?? FirebasePublishReturnRouteCallableInvoker();

  @override
  Future<PublishedReturnRoute> publish({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
    required int validForSeconds,
  }) async {
    if (origin == destination) {
      throw ArgumentError('Origin ve destination aynı olamaz.');
    }
    if (validForSeconds < 900 || validForSeconds > 14400) {
      throw ArgumentError.value(
        validForSeconds,
        'validForSeconds',
        '900 ile 14400 arasında olmalıdır.',
      );
    }

    await _authSession.requireAuthenticatedUser();
    final rawResponse = await _invoker.call({
      'origin': {'latitude': origin.latitude, 'longitude': origin.longitude},
      'destination': {
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
      'validForSeconds': validForSeconds,
    });
    return _mapResponse(rawResponse, origin: origin, destination: destination);
  }

  PublishedReturnRoute _mapResponse(
    Object? rawResponse, {
    required GeoCoordinate origin,
    required GeoCoordinate destination,
  }) {
    try {
      if (rawResponse is! Map) throw const FormatException();
      final data = Map<String, Object?>.from(rawResponse);
      final routeId = _requiredString(data, 'routeId');
      final driverId = _requiredString(data, 'driverId');
      if (data['status'] != 'active') throw const FormatException();
      final activatedAtMillis = _requiredInt(
        data,
        'activatedAtMillis',
        minimum: 0,
      );
      final expiresAtMillis = _requiredInt(data, 'expiresAtMillis', minimum: 1);
      if (expiresAtMillis <= activatedAtMillis) throw const FormatException();
      final distanceMeters = _requiredInt(data, 'distanceMeters', minimum: 1);
      final durationSeconds = _requiredInt(data, 'durationSeconds', minimum: 1);
      final encodedPolyline = _requiredString(data, 'encodedPolyline');
      final points = GeoPolylineDecoder.decode(encodedPolyline);
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
        createdAt: activatedAt,
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
    } on FormatException {
      throw const FormatException('Dönüş rotası yanıtı geçersiz.');
    } catch (_) {
      throw const FormatException('Dönüş rotası yanıtı geçersiz.');
    }
  }

  String _requiredString(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) throw const FormatException();
    return value;
  }

  int _requiredInt(
    Map<String, Object?> data,
    String key, {
    required int minimum,
  }) {
    final value = data[key];
    if (value is! int || value < minimum) throw const FormatException();
    return value;
  }
}
