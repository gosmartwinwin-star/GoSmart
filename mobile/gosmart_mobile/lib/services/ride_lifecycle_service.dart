import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import '../application/ride/ride_gateway.dart';
import '../domain/ride/canonical_ride.dart';

abstract interface class RideCallableInvoker {
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> payload);
}

class FirebaseRideCallableInvoker implements RideCallableInvoker {
  FirebaseRideCallableInvoker({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instanceFor(app: Firebase.app(), region: RideLifecycleService.region);
  final FirebaseFunctions _functions;
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> payload) async {
    try {
      final result = await _functions.httpsCallable(name).call(payload);
      if (result.data is! Map) throw const FormatException();
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      throw RideGatewayException(error.code, reason: details is Map ? details['reason'] as String? : null);
    }
  }
}

class RideLifecycleService implements RideGateway {
  RideLifecycleService({FirebaseFunctions? functions, RideCallableInvoker? invoker})
    : _invoker = invoker ?? FirebaseRideCallableInvoker(functions: functions);
  static const region = 'europe-west1';
  final RideCallableInvoker _invoker;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> payload) async {
    try {
      return await _invoker.call(name, payload);
    } on RideGatewayException {
      rethrow;
    } catch (_) {
      throw const RideGatewayException('invalid-response');
    }
  }

  @override
  Future<CanonicalRide?> getMyActiveRide() => _recover('getMyActiveRide');
  @override
  Future<CanonicalRide?> getMyActiveDriverRide() => _recover('getMyActiveDriverRide');
  Future<CanonicalRide?> _recover(String name) async {
    final data = await _call(name, const {});
    final active = data['activeRide'];
    if (active == null) return null;
    if (active is! Map) throw const RideGatewayException('invalid-response');
    return CanonicalRide.fromMap(Map<String, dynamic>.from(active));
  }

  @override
  Future<CanonicalRide> createRide({required String requestId, required RideLocation pickup, required RideLocation dropoff}) async {
    final data = await _call('createRideRequest', {
      'requestId': requestId,
      'pickup': {'latitude': pickup.latitude, 'longitude': pickup.longitude, 'addressLabel': pickup.addressLabel},
      'dropoff': {'latitude': dropoff.latitude, 'longitude': dropoff.longitude, 'addressLabel': dropoff.addressLabel},
    });
    return CanonicalRide.fromMap({...data, 'pickup': _locationMap(pickup), 'dropoff': _locationMap(dropoff), 'route': {
      'distanceMeters': data['distanceMeters'], 'durationSeconds': data['durationSeconds'], 'encodedPolyline': data['encodedPolyline'], 'computedAtMillis': data['createdAtMillis'],
    }, 'driverId': null, 'updatedAtMillis': data['createdAtMillis']});
  }

  Map<String, dynamic> _locationMap(RideLocation value) => {'latitude': value.latitude, 'longitude': value.longitude, 'addressLabel': value.addressLabel};
  Future<void> _mutation(String name, String rideId, String requestId, int version, [String? reason]) async {
    await _call(name, {'rideId': rideId, 'requestId': requestId, 'expectedVersion': version, 'reasonCode': ?reason});
  }
  @override
  Future<void> cancel({required String rideId, required String requestId, required int expectedVersion, required bool driver}) => _mutation('cancelRide', rideId, requestId, expectedVersion, driver ? 'driver_cancelled' : 'passenger_cancelled');
  @override
  Future<void> markDriverArrived({required String rideId, required String requestId, required int expectedVersion}) => _mutation('markDriverArrived', rideId, requestId, expectedVersion);
  @override
  Future<void> startRide({required String rideId, required String requestId, required int expectedVersion}) => _mutation('startRide', rideId, requestId, expectedVersion);
  @override
  Future<void> completeRide({required String rideId, required String requestId, required int expectedVersion}) => _mutation('completeRide', rideId, requestId, expectedVersion);
}
