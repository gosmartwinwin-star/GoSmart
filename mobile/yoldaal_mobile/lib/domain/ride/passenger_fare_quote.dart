class PassengerFareQuote {
  const PassengerFareQuote({
    required this.quoteId,
    required this.pricingVersion,
    required this.currency,
    required this.plannedDistanceMeters,
    required this.plannedDurationSeconds,
    required this.referenceEstimatedFareMinor,
    required this.yoldaalFareMinor,
    required this.savingMinor,
    required this.quotedAtMillis,
  });

  static const pricingVersionV1 = 'fare-v1';
  static const currencyTry = 'TRY';
  static const _maxSafeInteger = 9007199254740991;
  static final RegExp _quoteIdPattern = RegExp(r'^[0-9a-f]{64}$');

  static const _expectedKeys = <String>{
    'quoteId',
    'pricingVersion',
    'currency',
    'plannedDistanceMeters',
    'plannedDurationSeconds',
    'referenceEstimatedFareMinor',
    'yoldaalFareMinor',
    'savingMinor',
    'quotedAtMillis',
  };

  final String quoteId;
  final String pricingVersion;
  final String currency;
  final int plannedDistanceMeters;
  final int plannedDurationSeconds;
  final int referenceEstimatedFareMinor;
  final int yoldaalFareMinor;
  final int savingMinor;
  final int quotedAtMillis;

  factory PassengerFareQuote.fromMap(Map<String, dynamic> raw) {
    if (raw.length != _expectedKeys.length ||
        !raw.keys.every(_expectedKeys.contains)) {
      throw const FormatException('fare-quote-response-keys-invalid');
    }

    final quoteId = raw['quoteId'];
    if (quoteId is! String || !_quoteIdPattern.hasMatch(quoteId)) {
      throw const FormatException('fare-quote-response-id-invalid');
    }

    if (raw['pricingVersion'] != pricingVersionV1 ||
        raw['currency'] != currencyTry) {
      throw const FormatException('fare-quote-response-version-invalid');
    }

    final plannedDistanceMeters = _nonNegativeInt(
      raw['plannedDistanceMeters'],
      'plannedDistanceMeters',
    );
    final plannedDurationSeconds = _nonNegativeInt(
      raw['plannedDurationSeconds'],
      'plannedDurationSeconds',
    );
    final referenceEstimatedFareMinor = _nonNegativeInt(
      raw['referenceEstimatedFareMinor'],
      'referenceEstimatedFareMinor',
    );
    final yoldaalFareMinor = _nonNegativeInt(
      raw['yoldaalFareMinor'],
      'yoldaalFareMinor',
    );
    final savingMinor = _nonNegativeInt(
      raw['savingMinor'],
      'savingMinor',
    );
    final quotedAtMillis = _nonNegativeInt(
      raw['quotedAtMillis'],
      'quotedAtMillis',
    );

    if (referenceEstimatedFareMinor != yoldaalFareMinor + savingMinor) {
      throw const FormatException('fare-quote-response-fare-mismatch');
    }

    return PassengerFareQuote(
      quoteId: quoteId,
      pricingVersion: pricingVersionV1,
      currency: currencyTry,
      plannedDistanceMeters: plannedDistanceMeters,
      plannedDurationSeconds: plannedDurationSeconds,
      referenceEstimatedFareMinor: referenceEstimatedFareMinor,
      yoldaalFareMinor: yoldaalFareMinor,
      savingMinor: savingMinor,
      quotedAtMillis: quotedAtMillis,
    );
  }

  static int _nonNegativeInt(Object? value, String field) {
    if (value is! int || value < 0 || value > _maxSafeInteger) {
      throw FormatException('fare-quote-response-$field-invalid');
    }
    return value;
  }
}
