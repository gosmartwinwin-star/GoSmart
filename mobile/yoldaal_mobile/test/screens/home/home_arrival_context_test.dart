import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/screens/home/home_screen.dart';

void main() {
  group('passenger active-ride arrival context', () {
    test('driverEnRoute shows approaching context with existing ETA', () {
      expect(
        passengerActiveRideArrivalContextText(
          status: RideStatus.driverEnRoute,
          isUpdating: false,
          etaSeconds: 180,
        ),
        'Sürücünüz yaklaşıyor • Tahmini varış: 180 sn',
      );
    });

    test('driverEnRoute keeps approaching context while updating', () {
      expect(
        passengerActiveRideArrivalContextText(
          status: RideStatus.driverEnRoute,
          isUpdating: true,
          etaSeconds: 180,
        ),
        'Sürücünüz yaklaşıyor • Konum güncelleniyor…',
      );
    });

    test('driverEnRoute without ETA still shows approaching context', () {
      expect(
        passengerActiveRideArrivalContextText(
          status: RideStatus.driverEnRoute,
          isUpdating: false,
          etaSeconds: null,
        ),
        'Sürücünüz yaklaşıyor',
      );
    });

    test('driverArrived always hides ETA and shows arrived context', () {
      expect(
        passengerActiveRideArrivalContextText(
          status: RideStatus.driverArrived,
          isUpdating: true,
          etaSeconds: 180,
        ),
        'Sürücünüz geldi',
      );
    });

    test('inProgress preserves existing ETA presentation', () {
      expect(
        passengerActiveRideArrivalContextText(
          status: RideStatus.inProgress,
          isUpdating: false,
          etaSeconds: 120,
        ),
        'Tahmini varış: 120 sn',
      );
    });

    test('inProgress preserves existing updating fallback', () {
      expect(
        passengerActiveRideArrivalContextText(
          status: RideStatus.inProgress,
          isUpdating: false,
          etaSeconds: null,
        ),
        'Sürücü konumu güncelleniyor…',
      );
    });

    test('non-active status has no arrival context', () {
      expect(
        passengerActiveRideArrivalContextText(
          status: RideStatus.matching,
          isUpdating: false,
          etaSeconds: null,
        ),
        isNull,
      );
    });
  });
}
