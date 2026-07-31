import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/matching/matching_policy.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_pass.dart';
import 'package:gosmart_mobile/domain/subscription/driver_access_policy.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';

void main() {
  final now = DateTime.utc(2026, 8, 1, 12);
  const accessPolicy = DriverAccessPolicy();

  DriverAccessPass pass({
    DriverPassStatus status = DriverPassStatus.active,
    DateTime? activatedAt,
    DateTime? expiresAt,
  }) {
    return DriverAccessPass(
      id: 'pass-1',
      driverId: 'driver-1',
      plan: DriverPassPlan.weekly,
      status: status,
      purchasedAt: now.subtract(const Duration(hours: 2)),
      activatedAt: activatedAt ?? now.subtract(const Duration(hours: 1)),
      expiresAt: expiresAt ?? now.add(const Duration(hours: 5)),
    );
  }

  group('DriverAccessPass', () {
    test('aktif paket geçerlilik aralığında erişim sağlar', () {
      expect(pass().isActiveAt(now), isTrue);
    });

    test('tam activatedAt anında erişim sağlar', () {
      final activation = now;

      expect(pass(activatedAt: activation).isActiveAt(activation), isTrue);
    });

    test('tam expiresAt anında erişimi kapatır', () {
      final expiration = now;

      expect(pass(expiresAt: expiration).isActiveAt(expiration), isFalse);
    });

    test('expiry sonrasında erişim sağlamaz', () {
      expect(
        pass(
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ).isActiveAt(now),
        isFalse,
      );
    });

    for (final status in [
      DriverPassStatus.pending,
      DriverPassStatus.cancelled,
      DriverPassStatus.expired,
    ]) {
      test('$status durumundaki paket erişim sağlamaz', () {
        expect(pass(status: status).isActiveAt(now), isFalse);
      });
    }

    test('gelecekte aktive olacak paket erişim sağlamaz', () {
      expect(
        pass(activatedAt: now.add(const Duration(seconds: 1))).isActiveAt(now),
        isFalse,
      );
    });

    test('aktif paketin kalan süresini döndürür', () {
      expect(pass().remainingAt(now), const Duration(hours: 5));
    });

    test('aktif olmayan pakette kalan süre sıfırdır', () {
      expect(
        pass(status: DriverPassStatus.pending).remainingAt(now),
        Duration.zero,
      );
    });

    test('active durumunda activatedAt zorunludur', () {
      expect(
        () => DriverAccessPass(
          id: 'pass-1',
          driverId: 'driver-1',
          plan: DriverPassPlan.daily,
          status: DriverPassStatus.active,
          purchasedAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('active durumunda expiresAt zorunludur', () {
      expect(
        () => DriverAccessPass(
          id: 'pass-1',
          driverId: 'driver-1',
          plan: DriverPassPlan.daily,
          status: DriverPassStatus.active,
          purchasedAt: now,
          activatedAt: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('expiresAt activatedAt öncesindeyse modeli reddeder', () {
      expect(
        () => pass(
          activatedAt: now,
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('boş id ve driverId değerlerini reddeder', () {
      expect(
        () => DriverAccessPass(
          id: ' ',
          driverId: 'driver-1',
          plan: DriverPassPlan.daily,
          status: DriverPassStatus.pending,
          purchasedAt: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => DriverAccessPass(
          id: 'pass-1',
          driverId: '',
          plan: DriverPassPlan.daily,
          status: DriverPassStatus.pending,
          purchasedAt: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('DriverAccessPolicy', () {
    test('null pass ile yeni eşleşme başlatmaz', () {
      expect(accessPolicy.canStartNewMatch(pass: null, now: now), isFalse);
    });

    test('aktif pass ile yeni eşleşme başlatır', () {
      expect(accessPolicy.canStartNewMatch(pass: pass(), now: now), isTrue);
    });

    test('aktif pass ile dönüş rotası yayınlar', () {
      expect(
        accessPolicy.canPublishReturnRoute(pass: pass(), now: now),
        isTrue,
      );
    });

    test('aktif pass ile teklif gönderir', () {
      expect(accessPolicy.canSendOffer(pass: pass(), now: now), isTrue);
    });

    test('süresi bitmiş pass ile yeni erişim işlemlerini reddeder', () {
      final expiredPass = pass(expiresAt: now);

      expect(
        accessPolicy.canStartNewMatch(pass: expiredPass, now: now),
        isFalse,
      );
      expect(
        accessPolicy.canPublishReturnRoute(pass: expiredPass, now: now),
        isFalse,
      );
      expect(accessPolicy.canSendOffer(pass: expiredPass, now: now), isFalse);
    });

    test('kabul edilmiş yolculuğu paket kontrolü olmadan sürdürür', () {
      expect(
        accessPolicy.canContinueAcceptedRide(rideAlreadyAccepted: true),
        isTrue,
      );
    });

    test('kabul edilmemiş yolculuğu devam ediyor saymaz', () {
      expect(
        accessPolicy.canContinueAcceptedRide(rideAlreadyAccepted: false),
        isFalse,
      );
    });

    test('aktif erişim sonucunu MatchingPolicy ile kullanır', () {
      final subscriptionActive = accessPolicy.canStartNewMatch(
        pass: pass(),
        now: now,
      );
      final evaluation = const MatchingPolicy().evaluate(
        subscriptionActive: subscriptionActive,
        deviation: RouteDeviationResult(
          pickupDetourMeters: 1000,
          pickupDetourSeconds: 300,
          dropoffDetourMeters: 1000,
          dropoffDetourSeconds: 300,
          pickupRouteIndex: 5,
          dropoffRouteIndex: 10,
        ),
      );

      expect(evaluation.isEligible, isTrue);
    });
  });

  test('paket planları Türkçe gösterim adlarını sağlar', () {
    expect(DriverPassPlan.daily.displayName, 'Günlük');
    expect(DriverPassPlan.weekly.displayName, 'Haftalık');
    expect(DriverPassPlan.monthly.displayName, 'Aylık');
    expect(DriverPassPlan.quarterly.displayName, '3 Aylık');
  });

  test('paket durumları Türkçe gösterim adlarını sağlar', () {
    expect(DriverPassStatus.pending.displayName, 'Beklemede');
    expect(DriverPassStatus.active.displayName, 'Aktif');
    expect(DriverPassStatus.expired.displayName, 'Süresi Doldu');
    expect(DriverPassStatus.cancelled.displayName, 'İptal Edildi');
  });
}
