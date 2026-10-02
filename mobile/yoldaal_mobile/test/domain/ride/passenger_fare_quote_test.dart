import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/domain/ride/passenger_fare_quote.dart';

void main() {
  Map<String, dynamic> validQuote({
    Map<String, dynamic> overrides = const {},
  }) => {
    'quoteId': 'a' * 64,
    'pricingVersion': 'fare-v1',
    'currency': 'TRY',
    'plannedDistanceMeters': 18200,
    'plannedDurationSeconds': 2400,
    'referenceEstimatedFareMinor': 68700,
    'yoldaalFareMinor': 27480,
    'savingMinor': 41220,
    'quotedAtMillis': 1757000000000,
    ...overrides,
  };

  test('parses exact passenger-safe quote DTO', () {
    final quote = PassengerFareQuote.fromMap(validQuote());

    expect(quote.quoteId, 'a' * 64);
    expect(quote.pricingVersion, 'fare-v1');
    expect(quote.currency, 'TRY');
    expect(quote.plannedDistanceMeters, 18200);
    expect(quote.plannedDurationSeconds, 2400);
    expect(quote.referenceEstimatedFareMinor, 68700);
    expect(quote.yoldaalFareMinor, 27480);
    expect(quote.savingMinor, 41220);
    expect(quote.quotedAtMillis, 1757000000000);
  });

  test('rejects missing and extra response fields', () {
    final missing = validQuote()..remove('savingMinor');
    expect(
      () => PassengerFareQuote.fromMap(missing),
      throwsFormatException,
    );

    expect(
      () => PassengerFareQuote.fromMap(
        validQuote(overrides: {'tariffZoneId': 'forbidden'}),
      ),
      throwsFormatException,
    );
  });

  test('rejects wrong pricing version or currency', () {
    expect(
      () => PassengerFareQuote.fromMap(
        validQuote(overrides: {'pricingVersion': 'fare-v2'}),
      ),
      throwsFormatException,
    );
    expect(
      () => PassengerFareQuote.fromMap(
        validQuote(overrides: {'currency': 'USD'}),
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed quote id and invalid numeric values', () {
    expect(
      () => PassengerFareQuote.fromMap(
        validQuote(overrides: {'quoteId': 'not-a-hash'}),
      ),
      throwsFormatException,
    );
    expect(
      () => PassengerFareQuote.fromMap(
        validQuote(overrides: {'plannedDistanceMeters': -1}),
      ),
      throwsFormatException,
    );
    expect(
      () => PassengerFareQuote.fromMap(
        validQuote(overrides: {'plannedDurationSeconds': 1.5}),
      ),
      throwsFormatException,
    );
  });

  test('rejects inconsistent passenger fare amounts', () {
    expect(
      () => PassengerFareQuote.fromMap(
        validQuote(overrides: {'savingMinor': 41219}),
      ),
      throwsFormatException,
    );
  });
}
