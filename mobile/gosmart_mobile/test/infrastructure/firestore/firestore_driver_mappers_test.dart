import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/driver/driver_profile_status.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_status.dart';
import 'package:gosmart_mobile/infrastructure/firestore/mappers/driver_access_pass_firestore_mapper.dart';
import 'package:gosmart_mobile/infrastructure/firestore/mappers/driver_profile_firestore_mapper.dart';

void main() {
  final created = DateTime.utc(2026, 1, 1);
  final approved = DateTime.utc(2026, 1, 2);

  Map<String, Object?> profileData() => {
    'authUserId': 'user-1',
    'status': 'approved',
    'createdAt': Timestamp.fromDate(created),
    'approvedAt': Timestamp.fromDate(approved),
    'suspendedAt': null,
  };

  Map<String, Object?> passData() => {
    'driverId': 'driver-1',
    'plan': 'monthly',
    'status': 'active',
    'purchasedAt': Timestamp.fromDate(created),
    'activatedAt': Timestamp.fromDate(approved),
    'expiresAt': Timestamp.fromDate(approved.add(const Duration(days: 30))),
  };

  group('DriverProfile mapper', () {
    test('approved profili ve document id değerini map eder', () {
      final result = mapDriverProfileDocument(
        documentId: 'driver-1',
        data: profileData(),
      );
      expect(result.id, 'driver-1');
      expect(result.status, DriverProfileStatus.approved);
      expect(result.createdAt.isUtc, isTrue);
    });

    for (final value in <Object?>[null, '', '   ']) {
      test('eksik veya boş authUserId reddedilir: $value', () {
        final data = profileData()..['authUserId'] = value;
        expect(
          () => mapDriverProfileDocument(documentId: 'driver-1', data: data),
          throwsFormatException,
        );
      });
    }

    for (final value in <Object?>[1, 'APPROVED', 'unknown']) {
      test('geçersiz status reddedilir: $value', () {
        final data = profileData()..['status'] = value;
        expect(
          () => mapDriverProfileDocument(documentId: 'driver-1', data: data),
          throwsFormatException,
        );
      });
    }

    for (final value in <Object?>[null, '2026-01-01']) {
      test('eksik veya yanlış createdAt reddedilir: $value', () {
        final data = profileData()..['createdAt'] = value;
        expect(
          () => mapDriverProfileDocument(documentId: 'driver-1', data: data),
          throwsFormatException,
        );
      });
    }

    test('opsiyonel null tarihler pending profilde kabul edilir', () {
      final data = profileData()
        ..['status'] = 'pendingReview'
        ..['approvedAt'] = null;
      expect(
        mapDriverProfileDocument(documentId: 'driver-1', data: data).approvedAt,
        isNull,
      );
    });

    test('yanlış opsiyonel timestamp tipi reddedilir', () {
      final data = profileData()..['suspendedAt'] = 1;
      expect(
        () => mapDriverProfileDocument(documentId: 'driver-1', data: data),
        throwsFormatException,
      );
    });

    test('domain tarih doğrulamasını FormatException olarak korur', () {
      final data = profileData()
        ..['approvedAt'] = Timestamp.fromDate(
          created.subtract(const Duration(seconds: 1)),
        );
      expect(
        () => mapDriverProfileDocument(documentId: 'driver-1', data: data),
        throwsFormatException,
      );
    });
  });

  group('DriverAccessPass mapper', () {
    test('aktif pass, enumlar ve document id map edilir', () {
      final result = mapDriverAccessPassDocument(
        documentId: 'pass-1',
        data: passData(),
      );
      expect(result.id, 'pass-1');
      expect(result.plan, DriverPassPlan.monthly);
      expect(result.status, DriverPassStatus.active);
      expect(result.purchasedAt.isUtc, isTrue);
    });

    for (final value in <Object?>[null, '', ' ']) {
      test('eksik veya boş driverId reddedilir: $value', () {
        final data = passData()..['driverId'] = value;
        expect(
          () => mapDriverAccessPassDocument(documentId: 'pass-1', data: data),
          throwsFormatException,
        );
      });
    }

    test('bilinmeyen plan reddedilir', () {
      final data = passData()..['plan'] = 'yearly';
      expect(
        () => mapDriverAccessPassDocument(documentId: 'pass-1', data: data),
        throwsFormatException,
      );
    });

    test('bilinmeyen status reddedilir', () {
      final data = passData()..['status'] = 'ACTIVE';
      expect(
        () => mapDriverAccessPassDocument(documentId: 'pass-1', data: data),
        throwsFormatException,
      );
    });

    for (final value in <Object?>[null, 1]) {
      test('eksik veya yanlış purchasedAt reddedilir: $value', () {
        final data = passData()..['purchasedAt'] = value;
        expect(
          () => mapDriverAccessPassDocument(documentId: 'pass-1', data: data),
          throwsFormatException,
        );
      });
    }

    test('pending pass opsiyonel null tarihleri kabul eder', () {
      final data = passData()
        ..['status'] = 'pending'
        ..['activatedAt'] = null
        ..['expiresAt'] = null;
      expect(
        mapDriverAccessPassDocument(documentId: 'pass-1', data: data).expiresAt,
        isNull,
      );
    });

    for (final field in ['activatedAt', 'expiresAt']) {
      test('active pass eksik $field alanını reddeder', () {
        final data = passData()..[field] = null;
        expect(
          () => mapDriverAccessPassDocument(documentId: 'pass-1', data: data),
          throwsFormatException,
        );
      });
    }

    test('yanlış opsiyonel timestamp ve tarih sırası reddedilir', () {
      expect(
        () => mapDriverAccessPassDocument(
          documentId: 'pass-1',
          data: passData()..['expiresAt'] = 'later',
        ),
        throwsFormatException,
      );
      expect(
        () => mapDriverAccessPassDocument(
          documentId: 'pass-1',
          data: passData()..['expiresAt'] = Timestamp.fromDate(created),
        ),
        throwsFormatException,
      );
    });
  });
}
