class RideParticipantFare {
  const RideParticipantFare({
    required this.quoteId,
    required this.currency,
    required this.yoldaalFareMinor,
  });

  static const currencyTry = 'TRY';
  static final RegExp _quoteIdPattern = RegExp(r'^[0-9a-f]{64}$');

  static const _expectedKeys = <String>{
    'quoteId',
    'currency',
    'yoldaalFareMinor',
  };

  final String quoteId;
  final String currency;
  final int yoldaalFareMinor;

  factory RideParticipantFare.fromMap(Object? raw) {
    final map = _exactStringMap(raw, _expectedKeys, 'ride-fare-invalid');

    final quoteId = map['quoteId'];
    if (quoteId is! String || !_quoteIdPattern.hasMatch(quoteId)) {
      throw const FormatException('ride-fare-quote-id-invalid');
    }

    if (map['currency'] != currencyTry) {
      throw const FormatException('ride-fare-currency-invalid');
    }

    return RideParticipantFare(
      quoteId: quoteId,
      currency: currencyTry,
      yoldaalFareMinor: _minorAmount(
        map['yoldaalFareMinor'],
        'ride-fare-amount-invalid',
      ),
    );
  }
}

class DriverRideMatchOfferFare {
  const DriverRideMatchOfferFare({
    required this.currency,
    required this.yoldaalFareMinor,
  });

  static const currencyTry = 'TRY';

  static const _expectedKeys = <String>{
    'currency',
    'yoldaalFareMinor',
  };

  final String currency;
  final int yoldaalFareMinor;

  factory DriverRideMatchOfferFare.fromMap(Object? raw) {
    final map = _exactStringMap(
      raw,
      _expectedKeys,
      'driver-offer-fare-invalid',
    );

    if (map['currency'] != currencyTry) {
      throw const FormatException('driver-offer-fare-currency-invalid');
    }

    return DriverRideMatchOfferFare(
      currency: currencyTry,
      yoldaalFareMinor: _minorAmount(
        map['yoldaalFareMinor'],
        'driver-offer-fare-amount-invalid',
      ),
    );
  }
}

Map<String, dynamic> _exactStringMap(
  Object? raw,
  Set<String> expectedKeys,
  String reason,
) {
  if (raw is! Map) {
    throw FormatException(reason);
  }

  final map = Map<Object?, Object?>.from(raw);
  if (map.length != expectedKeys.length ||
      map.keys.any(
        (key) => key is! String || !expectedKeys.contains(key),
      )) {
    throw FormatException(reason);
  }

  return Map<String, dynamic>.from(map);
}

int _minorAmount(Object? value, String reason) {
  const maxSafeInteger = 9007199254740991;
  if (value is! int || value < 0 || value > maxSafeInteger) {
    throw FormatException(reason);
  }
  return value;
}
