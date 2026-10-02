import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/passenger_fare_quote_gateway.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/services/passenger_fare_quote_service.dart';

void main() {
  const pickup = RideLocation(
    latitude: 39.9208,
    longitude: 32.8541,
    addressLabel: 'Pickup',
  );
  const dropoff = RideLocation(
    latitude: 39.9308,
    longitude: 32.8641,
    addressLabel: 'Dropoff',
  );

  Map<String, dynamic> quoteResponse({
    Map<String, dynamic> overrides = const {},
  }) => {
    'quoteId': 'a' * 64,
    'pricingVersion': 'fare-v1',
    'currency': 'TRY',
    'plannedDistanceMeters': 10000,
    'plannedDurationSeconds': 1200,
    'referenceEstimatedFareMinor': 50000,
    'yoldaalFareMinor': 20000,
    'savingMinor': 30000,
    'quotedAtMillis': 1757000000000,
    ...overrides,
  };

  test('uses europe-west1 callable contract', () {
    expect(PassengerFareQuoteService.region, 'europe-west1');
    expect(PassengerFareQuoteService.callableName, 'createFareQuote');
  });

  test('sends exact requestId pickup dropoff payload', () async {
    final invoker = _FakeInvoker()..response = quoteResponse();
    final service = PassengerFareQuoteService(invoker: invoker);

    final quote = await service.createQuote(
      requestId: 'request_1234567890',
      pickup: pickup,
      dropoff: dropoff,
    );

    expect(invoker.name, 'createFareQuote');
    expect(invoker.payload, {
      'requestId': 'request_1234567890',
      'pickup': {
        'latitude': 39.9208,
        'longitude': 32.8541,
        'addressLabel': 'Pickup',
      },
      'dropoff': {
        'latitude': 39.9308,
        'longitude': 32.8641,
        'addressLabel': 'Dropoff',
      },
    });
    expect(quote.yoldaalFareMinor, 20000);

    for (final forbidden in [
      'passengerId',
      'uid',
      'tariffZoneId',
      'tariffVersionId',
      'farePolicyVersionId',
      'referenceEstimatedFareMinor',
      'yoldaalFareMinor',
      'savingMinor',
      'distanceMeters',
      'durationSeconds',
    ]) {
      expect(invoker.payload?.containsKey(forbidden), isFalse);
    }
  });

  test('maps malformed callable response to invalid-response', () async {
    final invoker = _FakeInvoker()
      ..response = quoteResponse(overrides: {'extra': true});
    final service = PassengerFareQuoteService(invoker: invoker);

    await expectLater(
      service.createQuote(
        requestId: 'request_1234567890',
        pickup: pickup,
        dropoff: dropoff,
      ),
      throwsA(
        isA<PassengerFareQuoteGatewayException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  test('preserves controlled gateway failure', () async {
    const expected = PassengerFareQuoteGatewayException(
      'failed-precondition',
      reason: 'fare_quote_tariff_unavailable',
    );
    final invoker = _FakeInvoker()..error = expected;
    final service = PassengerFareQuoteService(invoker: invoker);

    await expectLater(
      service.createQuote(
        requestId: 'request_1234567890',
        pickup: pickup,
        dropoff: dropoff,
      ),
      throwsA(same(expected)),
    );
  });
}

class _FakeInvoker implements PassengerFareQuoteCallableInvoker {
  Map<String, dynamic> response = {};
  PassengerFareQuoteGatewayException? error;
  String? name;
  Map<String, dynamic>? payload;

  @override
  Future<Map<String, dynamic>> call(
    String value,
    Map<String, dynamic> data,
  ) async {
    name = value;
    payload = Map<String, dynamic>.from(data);
    if (error case final failure?) {
      throw failure;
    }
    return response;
  }
}
