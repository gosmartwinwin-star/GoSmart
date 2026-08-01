import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_work_type.dart';
import 'package:gosmart_mobile/domain/driver_application/registration_owner_type.dart';

void main() {
  test('üç çalışma ve üç ruhsat sahibi tipi tanımlıdır', () {
    expect(DriverWorkType.values, hasLength(3));
    expect(RegistrationOwnerType.values, hasLength(3));
  });

  test('yedi zorunlu belge tipi tanımlıdır', () {
    expect(DriverApplicationDocumentType.values, hasLength(7));
  });

  test(
    'profil fotoğrafı yalnızca görüntü kabul eder ve 5 MiB ile sınırlıdır',
    () {
      final type = DriverApplicationDocumentType.driverProfilePhoto;
      expect(
        type.allowedContentTypes,
        containsAll(['image/jpeg', 'image/png']),
      );
      expect(type.allowedContentTypes, isNot(contains('application/pdf')));
      expect(type.maximumSizeBytes, 5 * 1024 * 1024);
    },
  );

  test('ruhsat ve adli sicil PDF kabul eder ve 10 MiB ile sınırlıdır', () {
    for (final type in [
      DriverApplicationDocumentType.vehicleRegistration,
      DriverApplicationDocumentType.criminalRecord,
    ]) {
      expect(type.allowedContentTypes, contains('application/pdf'));
      expect(type.maximumSizeBytes, 10 * 1024 * 1024);
    }
  });
}
