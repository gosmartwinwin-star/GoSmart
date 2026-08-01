import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_document_upload_gateway.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_document_upload_result.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_file_picker.dart';
import 'package:gosmart_mobile/application/driver_application/submit_driver_application_gateway.dart';
import 'package:gosmart_mobile/application/driver_application/vehicle_catalog_repository.dart';
import 'package:gosmart_mobile/controllers/driver_application_form_controller.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_work_type.dart';
import 'package:gosmart_mobile/domain/driver_application/registration_owner_type.dart';
import 'package:gosmart_mobile/domain/driver_application/vehicle_catalog.dart';

class UserInfo implements DriverApplicationUserInfoProvider {
  @override
  String? verifiedPhoneNumber = '+905000000000';
}

class Picker implements DriverApplicationFilePicker {
  PickedDriverApplicationFile? value = PickedDriverApplicationFile(
    bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
    contentType: 'image/jpeg',
  );
  @override
  Future<PickedDriverApplicationFile?> pickFromCamera({
    required documentType,
  }) async => value;
  @override
  Future<PickedDriverApplicationFile?> pickFromGallery({
    required documentType,
  }) async => value;
  @override
  Future<PickedDriverApplicationFile?> pickPdf({required documentType}) async =>
      value;
}

class Uploader implements DriverApplicationDocumentUploadGateway {
  int calls = 0;
  Object? error;
  Completer<void>? wait;
  @override
  Future<DriverApplicationDocumentUploadResult> upload({
    required documentType,
    required Uint8List bytes,
    required String contentType,
  }) async {
    calls++;
    if (error != null) throw error!;
    await wait?.future;
    return DriverApplicationDocumentUploadResult(
      documentType: documentType,
      storagePath: 'canonical',
      contentType: contentType,
      sizeBytes: bytes.length,
      uploadedAt: DateTime.utc(2026),
    );
  }
}

class Submitter implements SubmitDriverApplicationGateway {
  int calls = 0;
  Completer<void>? wait;
  @override
  Future<SubmittedDriverApplication> submit({
    required fullName,
    email,
    driverTaxiStandName,
    driverTaxiStandAddress,
    required workType,
    required vehiclePlate,
    required vehicleBrand,
    required vehicleModel,
    required vehicleModelYear,
    required registrationOwnerType,
    required hasVehicleUseAuthorization,
    vehicleTaxiStandName,
    required informationAccuracyAccepted,
    required documentValidityNotificationAccepted,
    required documentProcessingNoticeAccepted,
    required kvkkNoticeAccepted,
    required termsAccepted,
    required marketingConsent,
  }) async {
    calls++;
    await wait?.future;
    return SubmittedDriverApplication(
      submittedAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      submissionVersion: 1,
    );
  }
}

class CatalogRepository implements VehicleCatalogRepository {
  Object? error;
  int calls = 0;
  @override
  Future<VehicleCatalog> load() async {
    calls++;
    if (error != null) throw error!;
    return VehicleCatalog(
      version: 1,
      brands: [
        VehicleBrand(name: 'Fiat', models: ['Egea', 'Linea']),
        VehicleBrand(name: 'Ford', models: ['Focus']),
      ],
    );
  }
}

DriverApplicationFormController create(
  Picker picker,
  Uploader uploader,
  Submitter submitter, {
  VehicleCatalogRepository? catalogRepository,
}) => DriverApplicationFormController(
  picker: picker,
  uploader: uploader,
  submitter: submitter,
  userInfo: UserInfo(),
  vehicleCatalogRepository: catalogRepository,
);
void validFirst(DriverApplicationFormController value) {
  value.fullName = 'Ali Veli';
  value.workType = DriverWorkType.vehicleOwner;
}

void validVehicle(DriverApplicationFormController value) {
  value.vehiclePlate = '06 ABC 123';
  value.vehicleBrand = 'Fiat';
  value.vehicleModel = 'Egea';
  value.vehicleModelYear = '2020';
  value.registrationOwnerType = RegistrationOwnerType.applicant;
}

void main() {
  test('katalog yüklenir ve marka değişince model temizlenir', () async {
    final repository = CatalogRepository();
    final value = create(
      Picker(),
      Uploader(),
      Submitter(),
      catalogRepository: repository,
    );
    await value.loadVehicleCatalog();
    await value.loadVehicleCatalog();
    expect(repository.calls, 1);
    value.selectVehicleBrand('Fiat');
    expect(value.availableVehicleModels, ['Egea', 'Linea']);
    value.selectVehicleModel('Egea');
    value.selectVehicleBrand('Ford');
    expect(value.effectiveVehicleModel, isNull);
  });

  test('manuel marka ve model gerçek backend değerlerini üretir', () async {
    final value = create(
      Picker(),
      Uploader(),
      Submitter(),
      catalogRepository: CatalogRepository(),
    );
    await value.loadVehicleCatalog();
    value.selectManualVehicleBrand();
    value.updateManualVehicleBrand('  Yerli Marka  ');
    value.updateManualVehicleModel('  Özel Model  ');
    value.selectVehicleModelYear(2024);
    expect(value.effectiveVehicleBrand, 'Yerli Marka');
    expect(value.effectiveVehicleModel, 'Özel Model');
    expect(value.selectedVehicleModelYear, 2024);
  });

  test('katalog hatası güvenli state üretir ve manuel giriş açıktır', () async {
    final repository = CatalogRepository()..error = StateError('raw');
    final value = create(
      Picker(),
      Uploader(),
      Submitter(),
      catalogRepository: repository,
    );
    await value.loadVehicleCatalog();
    expect(value.vehicleCatalogErrorMessage, 'Araç listesi yüklenemedi.');
    value.selectManualVehicleBrand();
    expect(value.isManualVehicleBrand, isTrue);
    expect(value.isManualVehicleModel, isTrue);
  });
  test('ilk adım seçili ve eksik ad/çalışma tipiyle ilerlenemez', () {
    final value = create(Picker(), Uploader(), Submitter());
    expect(value.currentStep, 0);
    value.next();
    expect(value.currentStep, 0);
    value.fullName = 'Ali';
    value.next();
    expect(value.currentStep, 0);
    value.workType = DriverWorkType.vehicleOwner;
    value.next();
    expect(value.currentStep, 1);
  });
  test('araç alanları ve yetkilendirme doğrulanır', () {
    final value = create(Picker(), Uploader(), Submitter());
    validFirst(value);
    value.next();
    expect(value.validateStep(1), isFalse);
    validVehicle(value);
    expect(value.validateStep(1), isTrue);
    value.registrationOwnerType = RegistrationOwnerType.company;
    expect(value.validateStep(1), isFalse);
    value.hasVehicleUseAuthorization = true;
    expect(value.validateStep(1), isTrue);
  });
  test('picker iptali state bozmadan döner', () async {
    final picker = Picker()..value = null;
    final value = create(picker, Uploader(), Submitter());
    await value.pickAndUpload(
      DriverApplicationDocumentType.criminalRecord,
      DriverApplicationPickSource.pdf,
    );
    expect(
      value.uploadStates[DriverApplicationDocumentType.criminalRecord],
      DriverApplicationUploadState.notSelected,
    );
  });
  test('upload state ve çift tıklama korunur', () async {
    final uploader = Uploader()..wait = Completer<void>();
    final value = create(Picker(), uploader, Submitter());
    final first = value.pickAndUpload(
      DriverApplicationDocumentType.criminalRecord,
      DriverApplicationPickSource.gallery,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      value.uploadStates[DriverApplicationDocumentType.criminalRecord],
      DriverApplicationUploadState.uploading,
    );
    await value.pickAndUpload(
      DriverApplicationDocumentType.criminalRecord,
      DriverApplicationPickSource.gallery,
    );
    expect(uploader.calls, 1);
    uploader.wait!.complete();
    await first;
    expect(
      value.uploadStates[DriverApplicationDocumentType.criminalRecord],
      DriverApplicationUploadState.uploaded,
    );
  });
  test(
    'yedi belge ve beş beyan submit için zorunludur, marketing değildir',
    () async {
      final value = create(Picker(), Uploader(), Submitter());
      validFirst(value);
      validVehicle(value);
      for (final type in DriverApplicationDocumentType.values) {
        await value.pickAndUpload(type, DriverApplicationPickSource.gallery);
      }
      expect(value.allDocumentsUploaded, isTrue);
      expect(value.canSubmit, isFalse);
      value.informationAccuracyAccepted =
          value.documentValidityNotificationAccepted =
              value.documentProcessingNoticeAccepted =
                  value.kvkkNoticeAccepted = value.termsAccepted = true;
      expect(value.canSubmit, isTrue);
      expect(value.marketingConsent, isFalse);
      expect(await value.submit(), isTrue);
      expect(value.submittedApplication, isNotNull);
      expect(value.fullName, isEmpty);
      expect(value.vehiclePlate, isEmpty);
    },
  );
}
