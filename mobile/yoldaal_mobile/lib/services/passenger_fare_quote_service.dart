import 'package:cloud_functions/cloud_functions.dart';

import '../application/ride/passenger_fare_quote_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import '../domain/ride/canonical_ride.dart';
import '../domain/ride/passenger_fare_quote.dart';

abstract interface class PassengerFareQuoteCallableInvoker {
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  );
}

typedef PassengerFareQuoteHttpsCaller =
    Future<Object?> Function(String name, Map<String, dynamic> payload);

class FirebasePassengerFareQuoteCallableInvoker
    implements PassengerFareQuoteCallableInvoker {
  FirebasePassengerFareQuoteCallableInvoker({
    FirebaseFunctions? functions,
    PassengerFareQuoteHttpsCaller? caller,
  }) : _caller =
           caller ??
           _firebaseCaller(functions ?? FirebaseFunctionsRegistry.client);

  final PassengerFareQuoteHttpsCaller _caller;

  static PassengerFareQuoteHttpsCaller _firebaseCaller(
    FirebaseFunctions functions,
  ) => (name, payload) async =>
      (await functions.httpsCallable(name).call(payload)).data;

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      final data = await _caller(name, payload);
      if (data is! Map) {
        throw const PassengerFareQuoteGatewayException('invalid-response');
      }
      return Map<String, dynamic>.from(data);
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map && details['reason'] is String
          ? details['reason'] as String
          : null;
      throw PassengerFareQuoteGatewayException(
        error.code,
        reason: reason,
      );
    } on PassengerFareQuoteGatewayException {
      rethrow;
    } catch (_) {
      throw const PassengerFareQuoteGatewayException('invalid-response');
    }
  }
}

class PassengerFareQuoteService implements PassengerFareQuoteGateway {
  PassengerFareQuoteService({
    PassengerFareQuoteCallableInvoker? invoker,
    FirebaseFunctions? functions,
  }) : _invoker =
           invoker ??
           FirebasePassengerFareQuoteCallableInvoker(functions: functions);

  static const region = FirebaseFunctionsRegistry.region;
  static const callableName = 'createFareQuote';

  final PassengerFareQuoteCallableInvoker _invoker;

  @override
  Future<PassengerFareQuote> createQuote({
    required String requestId,
    required RideLocation pickup,
    required RideLocation dropoff,
  }) async {
    final response = await _invoker.call(
      callableName,
      {
        'requestId': requestId,
        'pickup': _locationMap(pickup),
        'dropoff': _locationMap(dropoff),
      },
    );

    try {
      return PassengerFareQuote.fromMap(response);
    } on FormatException {
      throw const PassengerFareQuoteGatewayException('invalid-response');
    }
  }

  static Map<String, dynamic> _locationMap(RideLocation value) => {
    'latitude': value.latitude,
    'longitude': value.longitude,
    'addressLabel': value.addressLabel,
  };
}
