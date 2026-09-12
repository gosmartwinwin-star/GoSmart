import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../application/ride/ride_live_tracking_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import '../domain/return_route/geo_coordinate.dart';

abstract interface class RideLiveTrackingAuthSession {
  Future<void> requireAuthenticatedUser();
}

abstract interface class RideLiveTrackingCallableInvoker {
  Future<Object?> call(Map<String, Object?> payload);
}

class FirebaseRideLiveTrackingAuthSession
    implements RideLiveTrackingAuthSession {
  FirebaseRideLiveTrackingAuthSession({
    FirebaseAuth? auth,
  }) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Future<void> requireAuthenticatedUser() async {
    if (_auth.currentUser == null) {
      throw const RideLiveTrackingException(
        code: 'unauthenticated',
      );
    }
  }
}

class FirebaseRideLiveTrackingCallableInvoker
    implements RideLiveTrackingCallableInvoker {
  FirebaseRideLiveTrackingCallableInvoker({
    FirebaseFunctions? functions,
  }) : _functions =
           functions ?? FirebaseFunctionsRegistry.client;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(
    Map<String, Object?> payload,
  ) async {
    try {
      final callable = _functions.httpsCallable(
        FirebaseFunctionsRegistry.getActiveRideDriverTracking,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 35),
        ),
      );

      final result =
          await callable.call<Map<String, Object?>>(payload);

      return result.data;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason =
          details is Map && details['reason'] is String
              ? details['reason'] as String
              : null;

      throw RideLiveTrackingException(
        code: error.code,
        reason: reason,
      );
    }
  }
}

class RideLiveTrackingService
    implements RideLiveTrackingGateway {
  RideLiveTrackingService({
    RideLiveTrackingAuthSession? authSession,
    RideLiveTrackingCallableInvoker? invoker,
  }) : _authSession =
           authSession ?? FirebaseRideLiveTrackingAuthSession(),
       _invoker =
           invoker ?? FirebaseRideLiveTrackingCallableInvoker();

  final RideLiveTrackingAuthSession _authSession;
  final RideLiveTrackingCallableInvoker _invoker;

  static const Set<String> _responseKeys = <String>{
    'latitude',
    'longitude',
    'updatedAtMillis',
    'etaSeconds',
    'etaUpdatedAtMillis',
  };

  @override
  Future<RideLiveTrackingSnapshot> getTracking({
    required String rideId,
  }) async {
    _validateRideId(rideId);
    await _authSession.requireAuthenticatedUser();

    final response = await _invoker.call(
      <String, Object?>{
        'rideId': rideId,
      },
    );

    if (response is! Map ||
        response.length != _responseKeys.length ||
        _responseKeys.any(
          (key) => !response.containsKey(key),
        )) {
      throw const FormatException(
        'Ride live tracking response is invalid.',
      );
    }

    final rawLatitude = response['latitude'];
    final rawLongitude = response['longitude'];
    final rawUpdatedAtMillis = response['updatedAtMillis'];
    final rawEtaSeconds = response['etaSeconds'];
    final rawEtaUpdatedAtMillis =
        response['etaUpdatedAtMillis'];

    GeoCoordinate? driverLocation;

    if (rawLatitude == null && rawLongitude == null) {
      driverLocation = null;
    } else {
      if (rawLatitude is! num ||
          rawLongitude is! num) {
        throw const FormatException(
          'Ride live tracking coordinates are invalid.',
        );
      }

      final latitude = rawLatitude.toDouble();
      final longitude = rawLongitude.toDouble();

      if (!latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        throw const FormatException(
          'Ride live tracking coordinates are invalid.',
        );
      }

      driverLocation = GeoCoordinate(
        latitude: latitude,
        longitude: longitude,
      );
    }

    final updatedAtMillis =
        _nullableNonNegativeInt(
          rawUpdatedAtMillis,
          'updatedAtMillis',
        );

    final etaSeconds =
        _nullableNonNegativeInt(
          rawEtaSeconds,
          'etaSeconds',
        );

    final etaUpdatedAtMillis =
        _nullableNonNegativeInt(
          rawEtaUpdatedAtMillis,
          'etaUpdatedAtMillis',
        );

    if (driverLocation != null &&
        updatedAtMillis == null) {
      throw const FormatException(
        'Ride live tracking timestamp is invalid.',
      );
    }

    if (etaSeconds != null &&
        etaUpdatedAtMillis == null) {
      throw const FormatException(
        'Ride live tracking ETA timestamp is invalid.',
      );
    }

    if (driverLocation == null &&
        etaSeconds != null) {
      throw const FormatException(
        'Ride live tracking ETA without location is invalid.',
      );
    }

    return RideLiveTrackingSnapshot(
      driverLocation: driverLocation,
      updatedAtMillis: updatedAtMillis,
      etaSeconds: etaSeconds,
      etaUpdatedAtMillis: etaUpdatedAtMillis,
    );
  }

  static int? _nullableNonNegativeInt(
    Object? value,
    String fieldName,
  ) {
    if (value == null) {
      return null;
    }

    if (value is! int || value < 0) {
      throw FormatException(
        'Ride live tracking $fieldName is invalid.',
      );
    }

    return value;
  }

  static void _validateRideId(String value) {
    if (value.isEmpty ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'rideId',
        'Ride ID is invalid.',
      );
    }
  }
}
