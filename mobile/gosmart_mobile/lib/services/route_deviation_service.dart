import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../application/matching/route_deviation_gateway.dart';
import '../domain/matching/matching_policy.dart';
import '../domain/return_route/geo_coordinate.dart';
import '../domain/return_route/route_anchor_result.dart';

class RouteDeviationServiceException implements Exception {
  final String message;

  const RouteDeviationServiceException(this.message);

  @override
  String toString() => message;
}

abstract interface class RouteDeviationCallableInvoker {
  Future<Object?> invoke(Map<String, Object?> payload);
}

class FirebaseRouteDeviationCallableInvoker
    implements RouteDeviationCallableInvoker {
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  FirebaseRouteDeviationCallableInvoker({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(
             app: Firebase.app(),
             region: 'europe-west1',
           );

  @override
  Future<Object?> invoke(Map<String, Object?> payload) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const RouteDeviationServiceException(
        'Oturumunuz bulunamadı. Lütfen yeniden giriş yapın.',
      );
    }

    try {
      await user.getIdToken(true);

      final callable = _functions.httpsCallable(
        'computeRouteDeviation',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
      );
      final result = await callable.call<Map<String, Object?>>(payload);
      return result.data;
    } on FirebaseAuthException {
      throw const RouteDeviationServiceException(
        'Oturum doğrulanamadı. Lütfen yeniden giriş yapın.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw RouteDeviationServiceException(_messageForCode(error.code));
    }
  }

  String _messageForCode(String code) {
    switch (code) {
      case 'unauthenticated':
        return 'Sürüş sapmasını hesaplamak için yeniden giriş yapmalısınız.';
      case 'invalid-argument':
        return 'Sürüş sapması ölçüm bilgileri geçersiz.';
      case 'failed-precondition':
        return 'Pickup ve dropoff rota yönü uyumlu değildir.';
      case 'deadline-exceeded':
        return 'Sürüş sapması ölçümü zaman aşımına uğradı.';
      case 'unavailable':
        return 'Sürüş sapması servisine şu anda ulaşılamıyor.';
      default:
        return 'Sürüş sapması ölçülürken beklenmeyen bir sorun oluştu.';
    }
  }
}

class RouteDeviationService implements RouteDeviationGateway {
  final RouteDeviationCallableInvoker _invoker;

  RouteDeviationService({RouteDeviationCallableInvoker? invoker})
    : _invoker = invoker ?? FirebaseRouteDeviationCallableInvoker();

  @override
  Future<RouteDeviationResult> compute({
    required RouteAnchorResult anchors,
    required GeoCoordinate pickup,
    required GeoCoordinate dropoff,
  }) async {
    if (!anchors.directionCompatible) {
      throw ArgumentError(
        'Pickup ve dropoff rota yönü uyumlu olmalıdır.',
        'anchors',
      );
    }

    final payload = <String, Object?>{
      'pickupAnchor': _coordinatePayload(anchors.pickupAnchor),
      'pickup': _coordinatePayload(pickup),
      'dropoff': _coordinatePayload(dropoff),
      'dropoffAnchor': _coordinatePayload(anchors.dropoffAnchor),
      'pickupRouteIndex': anchors.pickupRouteIndex,
      'dropoffRouteIndex': anchors.dropoffRouteIndex,
    };

    final rawData = await _invoker.invoke(payload);
    if (rawData is! Map) {
      throw const RouteDeviationServiceException(
        'Sürüş sapması servisinden geçersiz bir yanıt alındı.',
      );
    }

    try {
      final data = Map<String, Object?>.from(rawData);
      final pickupDetourMeters = _readNonNegativeInt(
        data,
        'pickupDetourMeters',
      );
      final pickupDetourSeconds = _readNonNegativeInt(
        data,
        'pickupDetourSeconds',
      );
      final dropoffDetourMeters = _readNonNegativeInt(
        data,
        'dropoffDetourMeters',
      );
      final dropoffDetourSeconds = _readNonNegativeInt(
        data,
        'dropoffDetourSeconds',
      );

      return RouteDeviationResult(
        pickupDetourMeters: pickupDetourMeters,
        pickupDetourSeconds: pickupDetourSeconds,
        dropoffDetourMeters: dropoffDetourMeters,
        dropoffDetourSeconds: dropoffDetourSeconds,
        pickupRouteIndex: anchors.pickupRouteIndex,
        dropoffRouteIndex: anchors.dropoffRouteIndex,
      );
    } on RouteDeviationServiceException {
      rethrow;
    } catch (_) {
      throw const RouteDeviationServiceException(
        'Sürüş sapması servisinden geçersiz bir yanıt alındı.',
      );
    }
  }

  Map<String, Object?> _coordinatePayload(GeoCoordinate coordinate) => {
    'latitude': coordinate.latitude,
    'longitude': coordinate.longitude,
  };

  int _readNonNegativeInt(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is! int || value < 0) {
      throw const RouteDeviationServiceException(
        'Sürüş sapması servisinden geçersiz bir yanıt alındı.',
      );
    }

    return value;
  }
}
