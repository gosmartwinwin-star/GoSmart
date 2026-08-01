import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_file_picker.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';

void main() {
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 1]);
  final png = Uint8List.fromList([
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ]);
  final pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2d]);
  test('JPEG PNG ve PDF magic byte tanınır', () {
    expect(detectDriverApplicationContentType(jpeg), 'image/jpeg');
    expect(detectDriverApplicationContentType(png), 'image/png');
    expect(detectDriverApplicationContentType(pdf), 'application/pdf');
  });
  test('boş ve bilinmeyen içerik reddedilir', () {
    expect(
      () => detectDriverApplicationContentType(Uint8List(0)),
      throwsFormatException,
    );
    expect(
      () => detectDriverApplicationContentType(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
  test('profil kimlik ve ehliyette PDF reddedilir', () {
    for (final type in [
      DriverApplicationDocumentType.driverProfilePhoto,
      DriverApplicationDocumentType.identityCardFront,
      DriverApplicationDocumentType.driverLicenseFront,
    ]) {
      expect(
        () =>
            validatePickedDriverApplicationFile(documentType: type, bytes: pdf),
        throwsFormatException,
      );
    }
  });
  test('ruhsat ve adli sicilde PDF kabul edilir', () {
    for (final type in [
      DriverApplicationDocumentType.vehicleRegistration,
      DriverApplicationDocumentType.criminalRecord,
    ]) {
      final result = validatePickedDriverApplicationFile(
        documentType: type,
        bytes: pdf,
      );
      expect(result.contentType, 'application/pdf');
    }
  });
  test('sonuç yerel yol UID veya URL taşımaz', () {
    final result = validatePickedDriverApplicationFile(
      documentType: DriverApplicationDocumentType.driverLicenseFront,
      bytes: jpeg,
    );
    expect(result.sizeBytes, jpeg.length);
  });
}
