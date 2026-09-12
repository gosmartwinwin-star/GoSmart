import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase/firebase_functions_registry.dart';

typedef NearbyPassengerDriverHttpsCaller =
    Future<Object?> Function(String name, Map<String, dynamic> payload);

class NearbyPassengerDriverProjection {
  const NearbyPassengerDriverProjection({
    required this.latitude,
    required this.longitude,
    required this.updatedAtMillis,
  });

  final double latitude;
  final double longitude;
  final int updatedAtMillis;
}

class NearbyPassengerDriverDiscoveryException implements Exception {
  const NearbyPassengerDriverDiscoveryException({
    required this.code,
    this.reason,
  });

  final String code;
  final String? reason;
}

class NearbyPassengerDriverService {
  NearbyPassengerDriverService({
    FirebaseFunctions? functions,
    NearbyPassengerDriverHttpsCaller? caller,
  }) : _caller =
           caller ??
           _firebaseCaller(functions ?? FirebaseFunctionsRegistry.client);

  static const callableName = 'getNearbyPassengerDrivers';

  final NearbyPassengerDriverHttpsCaller _caller;

  static NearbyPassengerDriverHttpsCaller _firebaseCaller(
    FirebaseFunctions functions,
  ) {
    return (name, payload) async {
      final result = await functions.httpsCallable(name).call(payload);
      return result.data;
    };
  }

  Future<List<NearbyPassengerDriverProjection>> load() async {
    try {
      final raw = await _caller(
        callableName,
        const <String, dynamic>{},
      );

      return _parseResponse(raw);
    } on NearbyPassengerDriverDiscoveryException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw NearbyPassengerDriverDiscoveryException(
        code: _safeFunctionCode(error.code),
        reason: _safeReason(error.details),
      );
    } catch (_) {
      throw const NearbyPassengerDriverDiscoveryException(
        code: 'unavailable',
      );
    }
  }

  static List<NearbyPassengerDriverProjection> _parseResponse(
    Object? raw,
  ) {
    if (raw is! List) {
      throw const NearbyPassengerDriverDiscoveryException(
        code: 'unavailable',
      );
    }

    final projections = <NearbyPassengerDriverProjection>[];

    for (final item in raw) {
      if (item is! Map) {
        throw const NearbyPassengerDriverDiscoveryException(
          code: 'unavailable',
        );
      }

      if (item.length != 3 ||
          !item.containsKey('latitude') ||
          !item.containsKey('longitude') ||
          !item.containsKey('updatedAtMillis')) {
        throw const NearbyPassengerDriverDiscoveryException(
          code: 'unavailable',
        );
      }

      final rawLatitude = item['latitude'];
      final rawLongitude = item['longitude'];
      final rawUpdatedAtMillis = item['updatedAtMillis'];

      if (rawLatitude is! num ||
          rawLongitude is! num ||
          rawUpdatedAtMillis is! int) {
        throw const NearbyPassengerDriverDiscoveryException(
          code: 'unavailable',
        );
      }

      final latitude = rawLatitude.toDouble();
      final longitude = rawLongitude.toDouble();

      if (!latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180 ||
          rawUpdatedAtMillis < 0) {
        throw const NearbyPassengerDriverDiscoveryException(
          code: 'unavailable',
        );
      }

      projections.add(
        NearbyPassengerDriverProjection(
          latitude: latitude,
          longitude: longitude,
          updatedAtMillis: rawUpdatedAtMillis,
        ),
      );
    }

    return List<NearbyPassengerDriverProjection>.unmodifiable(
      projections,
    );
  }

  static String _safeFunctionCode(String code) {
    const allowed = <String>{
      'unauthenticated',
      'invalid-argument',
      'failed-precondition',
      'internal',
      'unavailable',
      'resource-exhausted',
    };

    return allowed.contains(code) ? code : 'unavailable';
  }

  static String? _safeReason(Object? details) {
    if (details is! Map) {
      return null;
    }

    final rawReason = details['reason'];

    if (rawReason is! String) {
      return null;
    }

    final reason = rawReason.trim();

    if (reason.isEmpty || reason.length > 128) {
      return null;
    }

    return reason;
  }
}
