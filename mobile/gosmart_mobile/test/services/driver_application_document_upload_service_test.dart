import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';
import 'package:gosmart_mobile/services/driver_application_document_upload_service.dart';

class FakeAuth implements DriverApplicationAuthUidProvider {
  @override
  final String? currentUid;
  FakeAuth(this.currentUid);
}

class FakeStorage implements DriverApplicationStorageInvoker {
  int calls = 0;
  String? path;
  String? contentType;
  Map<String, String>? metadata;
  Object? error;

  @override
  Future<DriverApplicationStorageUploadResponse> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  }) async {
    calls++;
    this.path = path;
    this.contentType = contentType;
    metadata = customMetadata;
    if (error != null) throw error!;
    return DriverApplicationStorageUploadResponse(
      uploadedAt: DateTime.utc(2026),
    );
  }
}

DriverApplicationDocumentUploadService service(
  FakeStorage storage, {
  String? uid = 'user-a',
}) => DriverApplicationDocumentUploadService(
  authUidProvider: FakeAuth(uid),
  storageInvoker: storage,
  now: () => DateTime.utc(2025),
);

void main() {
  test('1 auth yoksa invoker çağrılmaz', () async {
    final storage = FakeStorage();
    await expectLater(
      service(storage, uid: null).upload(
        documentType: DriverApplicationDocumentType.driverLicenseFront,
        bytes: Uint8List(1),
        contentType: 'image/jpeg',
      ),
      throwsStateError,
    );
    expect(storage.calls, 0);
  });

  test('2 boş bytes reddedilir', () async {
    final storage = FakeStorage();
    await expectLater(
      service(storage).upload(
        documentType: DriverApplicationDocumentType.driverLicenseFront,
        bytes: Uint8List(0),
        contentType: 'image/jpeg',
      ),
      throwsArgumentError,
    );
    expect(storage.calls, 0);
  });

  test('3-7 canonical yol ve güvenilir metadata üretilir', () async {
    final storage = FakeStorage();
    await service(storage).upload(
      documentType: DriverApplicationDocumentType.identityCardFront,
      bytes: Uint8List(1),
      contentType: 'image/png',
    );
    expect(
      storage.path,
      'driverApplicationUploads/user-a/identityCardFront/current',
    );
    expect(storage.metadata, {
      'documentType': 'identityCardFront',
      'ownerUid': 'user-a',
    });
  });

  for (final entry in [
    (8, DriverApplicationDocumentType.driverLicenseFront, 'image/jpeg', true),
    (9, DriverApplicationDocumentType.identityCardFront, 'image/png', true),
    (
      10,
      DriverApplicationDocumentType.driverLicenseFront,
      'application/pdf',
      false,
    ),
    (11, DriverApplicationDocumentType.driverProfilePhoto, 'image/jpeg', true),
    (
      12,
      DriverApplicationDocumentType.driverProfilePhoto,
      'application/pdf',
      false,
    ),
    (
      13,
      DriverApplicationDocumentType.vehicleRegistration,
      'application/pdf',
      true,
    ),
    (14, DriverApplicationDocumentType.criminalRecord, 'application/pdf', true),
  ]) {
    test('${entry.$1} MIME doğrulaması', () async {
      final operation = service(FakeStorage()).upload(
        documentType: entry.$2,
        bytes: Uint8List(1),
        contentType: entry.$3,
      );
      if (entry.$4) {
        await expectLater(operation, completes);
      } else {
        await expectLater(operation, throwsArgumentError);
      }
    });
  }

  for (final entry in [
    (
      15,
      DriverApplicationDocumentType.driverProfilePhoto,
      5 * 1024 * 1024,
      true,
    ),
    (
      16,
      DriverApplicationDocumentType.driverProfilePhoto,
      5 * 1024 * 1024 + 1,
      false,
    ),
    (17, DriverApplicationDocumentType.criminalRecord, 10 * 1024 * 1024, true),
    (
      18,
      DriverApplicationDocumentType.criminalRecord,
      10 * 1024 * 1024 + 1,
      false,
    ),
  ]) {
    test('${entry.$1} boyut doğrulaması', () async {
      final storage = FakeStorage();
      final operation = service(storage).upload(
        documentType: entry.$2,
        bytes: Uint8List(entry.$3),
        contentType: 'image/jpeg',
      );
      if (entry.$4) {
        await expectLater(operation, completes);
        expect(storage.calls, 1);
      } else {
        await expectLater(operation, throwsArgumentError);
        expect(storage.calls, 0);
      }
    });
  }

  test('19-20 Storage hatası başarıya çevrilmez', () async {
    final storage = FakeStorage()..error = StateError('storage failed');
    await expectLater(
      service(storage).upload(
        documentType: DriverApplicationDocumentType.driverLicenseFront,
        bytes: Uint8List(1),
        contentType: 'image/jpeg',
      ),
      throwsStateError,
    );
  });

  test('21-22 sonuç download URL içermez ve canonical path taşır', () async {
    final result = await service(FakeStorage()).upload(
      documentType: DriverApplicationDocumentType.criminalRecord,
      bytes: Uint8List(1),
      contentType: 'application/pdf',
    );
    expect(
      result.storagePath,
      'driverApplicationUploads/user-a/criminalRecord/current',
    );
    expect(result.uploadedAt.isUtc, isTrue);
  });
}
