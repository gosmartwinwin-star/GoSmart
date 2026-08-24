class GeoCoordinate {
  final double latitude;
  final double longitude;

  const GeoCoordinate._({required this.latitude, required this.longitude});

  factory GeoCoordinate({required double latitude, required double longitude}) {
    if (!latitude.isFinite) {
      throw ArgumentError.value(latitude, 'latitude', 'Sonlu sayı olmalıdır.');
    }
    if (!longitude.isFinite) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Sonlu sayı olmalıdır.',
      );
    }
    if (latitude < -90 || latitude > 90) {
      throw RangeError.range(latitude, -90, 90, 'latitude');
    }
    if (longitude < -180 || longitude > 180) {
      throw RangeError.range(longitude, -180, 180, 'longitude');
    }

    return GeoCoordinate._(latitude: latitude, longitude: longitude);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GeoCoordinate &&
            latitude == other.latitude &&
            longitude == other.longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);
}
