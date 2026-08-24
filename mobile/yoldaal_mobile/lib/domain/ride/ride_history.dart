import 'canonical_ride.dart';

enum RideHistoryScope { passenger, driver }

class RideHistoryCursor {
  const RideHistoryCursor({
    required this.updatedAtMillis,
    required this.rideId,
  });

  final int updatedAtMillis;
  final String rideId;

  Map<String, Object?> toMap() => {
    'updatedAtMillis': updatedAtMillis,
    'rideId': rideId,
  };

  factory RideHistoryCursor.fromObject(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid ride history cursor.');
    }

    final map = Map<String, dynamic>.from(value);
    final updatedAtMillis = map['updatedAtMillis'];
    final rideId = map['rideId'];

    if (updatedAtMillis is! num ||
        updatedAtMillis != updatedAtMillis.roundToDouble() ||
        updatedAtMillis < 0 ||
        rideId is! String ||
        rideId.isEmpty) {
      throw const FormatException('Invalid ride history cursor.');
    }

    return RideHistoryCursor(
      updatedAtMillis: updatedAtMillis.toInt(),
      rideId: rideId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideHistoryCursor &&
          updatedAtMillis == other.updatedAtMillis &&
          rideId == other.rideId;

  @override
  int get hashCode => Object.hash(updatedAtMillis, rideId);
}

class RideHistoryPage {
  const RideHistoryPage({required this.rides, required this.nextCursor});

  final List<CanonicalRide> rides;
  final RideHistoryCursor? nextCursor;
}
