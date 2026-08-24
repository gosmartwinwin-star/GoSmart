import 'canonical_ride.dart';

class RideMatchOffer {
  const RideMatchOffer({
    required this.rideId,
    required this.rideVersion,
    required this.pickup,
    required this.dropoff,
    required this.expiresAt,
  });

  final String rideId;
  final int rideVersion;
  final RideLocation pickup;
  final RideLocation dropoff;
  final DateTime expiresAt;

  static const _publicKeys = <String>{
    'rideId',
    'rideVersion',
    'pickup',
    'dropoff',
    'expiresAtMillis',
  };

  static const _locationKeys = <String>{
    'latitude',
    'longitude',
    'addressLabel',
  };

  factory RideMatchOffer.fromMap(Map<String, dynamic> map) {
    if (map.length != _publicKeys.length ||
        map.keys.any((key) => !_publicKeys.contains(key))) {
      throw const FormatException('Invalid ride match offer payload.');
    }

    final rideId = map['rideId'];
    final rideVersion = _positiveInteger(map['rideVersion']);
    final expiresAtMillis = _positiveInteger(map['expiresAtMillis']);

    if (rideId is! String ||
        rideId.isEmpty ||
        rideId.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(rideId) ||
        rideVersion == null ||
        expiresAtMillis == null) {
      throw const FormatException('Invalid ride match offer payload.');
    }

    late final DateTime expiresAt;

    try {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAtMillis,
        isUtc: true,
      );
    } catch (_) {
      throw const FormatException('Invalid ride match offer expiry.');
    }

    return RideMatchOffer(
      rideId: rideId,
      rideVersion: rideVersion,
      pickup: _location(map['pickup']),
      dropoff: _location(map['dropoff']),
      expiresAt: expiresAt,
    );
  }

  static int? _positiveInteger(Object? value) {
    if (value is int) {
      return value > 0 ? value : null;
    }

    if (value is num &&
        value.isFinite &&
        value == value.roundToDouble() &&
        value > 0) {
      return value.toInt();
    }

    return null;
  }

  static RideLocation _location(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid ride match offer location.');
    }

    final data = Map<Object?, Object?>.from(value);

    if (data.length != _locationKeys.length ||
        data.keys.any(
          (key) => key is! String || !_locationKeys.contains(key),
        )) {
      throw const FormatException('Invalid ride match offer location.');
    }

    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final addressLabel = data['addressLabel'];

    if (latitude is! num || longitude is! num || addressLabel is! String) {
      throw const FormatException('Invalid ride match offer location.');
    }

    final latitudeValue = latitude.toDouble();
    final longitudeValue = longitude.toDouble();
    final normalizedLabel = addressLabel.trim();

    final hasControlCharacter = addressLabel.runes.any(
      (codePoint) => codePoint <= 31 || codePoint == 127,
    );

    if (!latitudeValue.isFinite ||
        latitudeValue < -90 ||
        latitudeValue > 90 ||
        !longitudeValue.isFinite ||
        longitudeValue < -180 ||
        longitudeValue > 180 ||
        normalizedLabel.isEmpty ||
        addressLabel.length > 300 ||
        hasControlCharacter) {
      throw const FormatException('Invalid ride match offer location.');
    }

    return RideLocation(
      latitude: latitudeValue,
      longitude: longitudeValue,
      addressLabel: normalizedLabel,
    );
  }
}
