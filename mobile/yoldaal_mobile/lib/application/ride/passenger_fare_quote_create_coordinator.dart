import '../../domain/ride/canonical_ride.dart';
import '../../domain/ride/passenger_fare_quote.dart';

typedef PassengerFareQuoteCreator =
    Future<PassengerFareQuote> Function({
      required String requestId,
      required RideLocation pickup,
      required RideLocation dropoff,
    });

typedef PassengerRideCreator =
    Future<CanonicalRide> Function({
      required String requestId,
      required RideLocation pickup,
      required RideLocation dropoff,
    });

class PassengerFareQuoteCreateException implements Exception {
  const PassengerFareQuoteCreateException(this.reason);

  final String reason;
}

class PassengerFareQuoteCreateResult {
  const PassengerFareQuoteCreateResult({
    required this.quote,
    required this.ride,
  });

  final PassengerFareQuote quote;
  final CanonicalRide ride;
}

class PassengerFareQuoteCreateCoordinator {
  const PassengerFareQuoteCreateCoordinator({
    required PassengerFareQuoteCreator createQuote,
    required PassengerRideCreator createRide,
  }) : _createQuote = createQuote,
       _createRide = createRide;

  final PassengerFareQuoteCreator _createQuote;
  final PassengerRideCreator _createRide;

  Future<PassengerFareQuoteCreateResult> create({
    required String requestId,
    required RideLocation pickup,
    required RideLocation dropoff,
  }) async {
    final quote = await _createQuote(
      requestId: requestId,
      pickup: pickup,
      dropoff: dropoff,
    );

    final ride = await _createRide(
      requestId: requestId,
      pickup: pickup,
      dropoff: dropoff,
    );

    final fare = ride.fare;
    if (fare == null ||
        fare.quoteId != quote.quoteId ||
        fare.currency != quote.currency ||
        fare.yoldaalFareMinor != quote.yoldaalFareMinor) {
      throw const PassengerFareQuoteCreateException(
        'fare-binding-mismatch',
      );
    }

    return PassengerFareQuoteCreateResult(
      quote: quote,
      ride: ride,
    );
  }
}
