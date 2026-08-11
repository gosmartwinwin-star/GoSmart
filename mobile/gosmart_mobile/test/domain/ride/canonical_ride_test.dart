import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';

void main() {
  Map<String, dynamic> data({String status = 'matching', Object version = 1}) => {
    'rideId': 'ride-1', 'status': status, 'version': version, 'driverId': null,
    'pickup': {'latitude': 41.0, 'longitude': 29.0, 'addressLabel': 'Alış'},
    'dropoff': {'latitude': 41.1, 'longitude': 29.1, 'addressLabel': 'Varış'},
    'route': {'distanceMeters': 1000, 'durationSeconds': 300, 'encodedPolyline': 'abc', 'computedAtMillis': null},
    'createdAtMillis': 1000, 'updatedAtMillis': 2000,
    'acceptedAtMillis': null, 'driverEnRouteAtMillis': null, 'arrivedAtMillis': null,
    'startedAtMillis': null, 'completedAtMillis': null, 'cancelledAtMillis': null, 'expiredAtMillis': null,
    'cancelledBy': null, 'terminalReason': null,
  };

  test('tüm canonical durumlar strict parse edilir', () {
    for (final status in RideStatus.values) {
      expect(CanonicalRide.fromMap(data(status: status.name)).status, status);
    }
  });
  test('bilinmeyen durum güvenli format hatasıdır', () => expect(() => CanonicalRide.fromMap(data(status: 'accepted')), throwsFormatException));
  test('version pozitif tam sayı olmalıdır', () { expect(() => CanonicalRide.fromMap(data(version: 0)), throwsFormatException); expect(() => CanonicalRide.fromMap(data(version: 1.5)), throwsFormatException); });
  test('konum rota ve nullable zamanlar parse edilir', () { final ride = CanonicalRide.fromMap(data()); expect(ride.pickup.addressLabel, 'Alış'); expect(ride.route.distanceMeters, 1000); expect(ride.acceptedAt, isNull); expect(ride.createdAt, DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true)); });
  test('malformed response reddedilir', () { final malformed = data()..remove('route'); expect(() => CanonicalRide.fromMap(malformed), throwsFormatException); });
}
