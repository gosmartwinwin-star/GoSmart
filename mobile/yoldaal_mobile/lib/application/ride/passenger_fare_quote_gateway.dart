import '../../domain/ride/canonical_ride.dart';
import '../../domain/ride/passenger_fare_quote.dart';

class PassengerFareQuoteGatewayException implements Exception {
  const PassengerFareQuoteGatewayException(this.code, {this.reason});

  final String code;
  final String? reason;
}

abstract interface class PassengerFareQuoteGateway {
  Future<PassengerFareQuote> createQuote({
    required String requestId,
    required RideLocation pickup,
    required RideLocation dropoff,
  });
}
