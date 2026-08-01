import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../application/driver_application/driver_application_document_upload_gateway.dart';
import '../application/driver_application/driver_application_file_picker.dart';
import '../application/driver_application/submit_driver_application_gateway.dart';
import '../application/driver_application/vehicle_catalog_repository.dart';
import '../domain/driver_application/driver_application_document_type.dart';
import '../domain/driver_application/driver_work_type.dart';
import '../domain/driver_application/registration_owner_type.dart';
import '../domain/driver_application/vehicle_catalog.dart';
import '../services/submit_driver_application_service.dart';

enum DriverApplicationUploadState {
  notSelected,
  selecting,
  uploading,
  uploaded,
  failed,
}

enum DriverApplicationPickSource { camera, gallery, pdf }

abstract interface class DriverApplicationUserInfoProvider {
  String? get verifiedPhoneNumber;
}

class FirebaseDriverApplicationUserInfoProvider
    implements DriverApplicationUserInfoProvider {
  final FirebaseAuth _auth;
  FirebaseDriverApplicationUserInfoProvider({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;
  @override
  String? get verifiedPhoneNumber => _auth.currentUser?.phoneNumber;
}

class DriverApplicationFormController extends ChangeNotifier {
  final DriverApplicationFilePicker _picker;
  final DriverApplicationDocumentUploadGateway _uploader;
  final SubmitDriverApplicationGateway _submitter;
  final DriverApplicationUserInfoProvider _userInfo;
  final VehicleCatalogRepository? _catalogRepository;

  int currentStep = 0;
  String fullName = '';
  String email = '';
  String driverTaxiStandName = '';
  String driverTaxiStandAddress = '';
  DriverWorkType? workType;
  String vehiclePlate = '';
  String vehicleBrand = '';
  String vehicleModel = '';
  String vehicleModelYear = '';
  bool isVehicleCatalogLoading = false;
  String? vehicleCatalogErrorMessage;
  VehicleCatalog? vehicleCatalog;
  String? selectedVehicleBrand;
  bool isManualVehicleBrand = false;
  String manualVehicleBrand = '';
  String? selectedVehicleModel;
  bool isManualVehicleModel = false;
  String manualVehicleModel = '';
  int? selectedVehicleModelYear;
  bool _catalogLoadAttempted = false;
  RegistrationOwnerType? registrationOwnerType;
  bool hasVehicleUseAuthorization = false;
  String vehicleTaxiStandName = '';
  bool informationAccuracyAccepted = false;
  bool documentValidityNotificationAccepted = false;
  bool documentProcessingNoticeAccepted = false;
  bool kvkkNoticeAccepted = false;
  bool termsAccepted = false;
  bool marketingConsent = false;
  bool isSubmitting = false;
  String? errorMessage;
  SubmittedDriverApplication? submittedApplication;
  bool _disposed = false;
  bool _uploadActive = false;

  late final Map<DriverApplicationDocumentType, DriverApplicationUploadState>
  uploadStates = {
    for (final type in DriverApplicationDocumentType.values)
      type: DriverApplicationUploadState.notSelected,
  };

  DriverApplicationFormController({
    required DriverApplicationFilePicker picker,
    required DriverApplicationDocumentUploadGateway uploader,
    required SubmitDriverApplicationGateway submitter,
    required DriverApplicationUserInfoProvider userInfo,
    VehicleCatalogRepository? vehicleCatalogRepository,
  }) : _picker = picker,
       _uploader = uploader,
       _submitter = submitter,
       _userInfo = userInfo,
       _catalogRepository = vehicleCatalogRepository;

  String? get effectiveVehicleBrand {
    final value = isManualVehicleBrand
        ? manualVehicleBrand
        : selectedVehicleBrand;
    return value?.trim().isEmpty == false ? value!.trim() : null;
  }

  String? get effectiveVehicleModel {
    final value = isManualVehicleModel
        ? manualVehicleModel
        : selectedVehicleModel;
    return value?.trim().isEmpty == false ? value!.trim() : null;
  }

  List<String> get availableVehicleModels {
    final brand = vehicleCatalog?.brands
        .where((item) => item.name == selectedVehicleBrand)
        .firstOrNull;
    return brand?.models ?? const [];
  }

  Future<void> loadVehicleCatalog() async {
    if (_catalogLoadAttempted || _catalogRepository == null) return;
    _catalogLoadAttempted = true;
    isVehicleCatalogLoading = true;
    _notify();
    try {
      vehicleCatalog = await _catalogRepository.load();
      vehicleCatalogErrorMessage = null;
    } catch (_) {
      vehicleCatalogErrorMessage = 'Araç listesi yüklenemedi.';
    } finally {
      isVehicleCatalogLoading = false;
      _notify();
    }
  }

  void selectVehicleBrand(String brand) {
    if (!vehicleCatalog!.brands.any((item) => item.name == brand)) {
      throw ArgumentError.value(brand);
    }
    final changedBrand = selectedVehicleBrand != brand || isManualVehicleBrand;
    selectedVehicleBrand = brand;
    isManualVehicleBrand = false;
    manualVehicleBrand = '';
    vehicleBrand = brand;
    if (changedBrand) _clearVehicleModel();
    _notify();
  }

  void selectManualVehicleBrand() {
    selectedVehicleBrand = null;
    isManualVehicleBrand = true;
    manualVehicleBrand = '';
    vehicleBrand = '';
    _clearVehicleModel(manual: true);
    _notify();
  }

  void updateManualVehicleBrand(String value) {
    manualVehicleBrand = value;
    vehicleBrand = value.trim();
    _notify();
  }

  void selectVehicleModel(String model) {
    if (selectedVehicleBrand == null ||
        !availableVehicleModels.contains(model)) {
      throw ArgumentError.value(model);
    }
    selectedVehicleModel = model;
    isManualVehicleModel = false;
    manualVehicleModel = '';
    vehicleModel = model;
    _notify();
  }

  void selectManualVehicleModel() {
    if (selectedVehicleBrand == null && !isManualVehicleBrand) {
      throw StateError('Önce marka seçilmelidir.');
    }
    selectedVehicleModel = null;
    isManualVehicleModel = true;
    manualVehicleModel = '';
    vehicleModel = '';
    _notify();
  }

  void updateManualVehicleModel(String value) {
    manualVehicleModel = value;
    vehicleModel = value.trim();
    _notify();
  }

  void selectVehicleModelYear(int year) {
    selectedVehicleModelYear = year;
    vehicleModelYear = year.toString();
    _notify();
  }

  void _clearVehicleModel({bool manual = false}) {
    selectedVehicleModel = null;
    isManualVehicleModel = manual;
    manualVehicleModel = '';
    vehicleModel = '';
    errorMessage = null;
  }

  String? get verifiedPhoneNumber => _userInfo.verifiedPhoneNumber;
  bool get allDocumentsUploaded => uploadStates.values.every(
    (state) => state == DriverApplicationUploadState.uploaded,
  );
  bool get declarationsAccepted =>
      informationAccuracyAccepted &&
      documentValidityNotificationAccepted &&
      documentProcessingNoticeAccepted &&
      kvkkNoticeAccepted &&
      termsAccepted;
  bool get authorizationValid =>
      registrationOwnerType == RegistrationOwnerType.applicant ||
      hasVehicleUseAuthorization;
  bool get canSubmit =>
      verifiedPhoneNumber?.trim().isNotEmpty == true &&
      validateStep(0) &&
      validateStep(1) &&
      allDocumentsUploaded &&
      declarationsAccepted &&
      !isSubmitting;

  bool validateStep(int step) => switch (step) {
    0 =>
      fullName.trim().isNotEmpty &&
          fullName.trim().length <= 80 &&
          (email.trim().isEmpty ||
              (email.length <= 254 && email.contains('@'))) &&
          driverTaxiStandName.length <= 100 &&
          driverTaxiStandAddress.length <= 250 &&
          workType != null &&
          verifiedPhoneNumber?.trim().isNotEmpty == true,
    1 =>
      vehiclePlate.trim().isNotEmpty &&
          vehiclePlate.length <= 15 &&
          (effectiveVehicleBrand ?? vehicleBrand.trim()).isNotEmpty &&
          (effectiveVehicleBrand ?? vehicleBrand.trim()).length <= 50 &&
          (effectiveVehicleModel ?? vehicleModel.trim()).isNotEmpty &&
          (effectiveVehicleModel ?? vehicleModel.trim()).length <= 80 &&
          (selectedVehicleModelYear != null ||
              RegExp(r'^\d{4}$').hasMatch(vehicleModelYear)) &&
          registrationOwnerType != null &&
          authorizationValid,
    2 => allDocumentsUploaded,
    3 => declarationsAccepted,
    _ => false,
  };

  void next() {
    if (currentStep < 3 && validateStep(currentStep)) {
      currentStep++;
      errorMessage = null;
      _notify();
    }
  }

  void previous() {
    if (currentStep > 0) currentStep--;
    _notify();
  }

  void changed() => _notify();

  Future<void> pickAndUpload(
    DriverApplicationDocumentType type,
    DriverApplicationPickSource source,
  ) async {
    if (_uploadActive ||
        uploadStates[type] == DriverApplicationUploadState.uploading) {
      return;
    }
    _uploadActive = true;
    uploadStates[type] = DriverApplicationUploadState.selecting;
    errorMessage = null;
    _notify();
    try {
      final file = switch (source) {
        DriverApplicationPickSource.camera => await _picker.pickFromCamera(
          documentType: type,
        ),
        DriverApplicationPickSource.gallery => await _picker.pickFromGallery(
          documentType: type,
        ),
        DriverApplicationPickSource.pdf => await _picker.pickPdf(
          documentType: type,
        ),
      };
      if (file == null) {
        uploadStates[type] = DriverApplicationUploadState.notSelected;
        return;
      }
      uploadStates[type] = DriverApplicationUploadState.uploading;
      _notify();
      await _uploader.upload(
        documentType: type,
        bytes: file.bytes,
        contentType: file.contentType,
      );
      uploadStates[type] = DriverApplicationUploadState.uploaded;
    } on FormatException {
      uploadStates[type] = DriverApplicationUploadState.failed;
      errorMessage = 'Bu dosya türü desteklenmiyor.';
    } catch (_) {
      uploadStates[type] = DriverApplicationUploadState.failed;
      errorMessage = 'Belge yüklenemedi. Lütfen tekrar deneyin.';
    } finally {
      _uploadActive = false;
      _notify();
    }
  }

  Future<bool> submit() async {
    if (!canSubmit) return false;
    isSubmitting = true;
    errorMessage = null;
    _notify();
    try {
      submittedApplication = await _submitter.submit(
        fullName: fullName.trim(),
        email: email,
        driverTaxiStandName: driverTaxiStandName,
        driverTaxiStandAddress: driverTaxiStandAddress,
        workType: workType!,
        vehiclePlate: vehiclePlate,
        vehicleBrand: effectiveVehicleBrand ?? vehicleBrand.trim(),
        vehicleModel: effectiveVehicleModel ?? vehicleModel.trim(),
        vehicleModelYear:
            selectedVehicleModelYear ?? int.parse(vehicleModelYear),
        registrationOwnerType: registrationOwnerType!,
        hasVehicleUseAuthorization: hasVehicleUseAuthorization,
        vehicleTaxiStandName: vehicleTaxiStandName,
        informationAccuracyAccepted: informationAccuracyAccepted,
        documentValidityNotificationAccepted:
            documentValidityNotificationAccepted,
        documentProcessingNoticeAccepted: documentProcessingNoticeAccepted,
        kvkkNoticeAccepted: kvkkNoticeAccepted,
        termsAccepted: termsAccepted,
        marketingConsent: marketingConsent,
      );
      _clearSensitiveState();
      return true;
    } on SubmitDriverApplicationException catch (error) {
      errorMessage = messageForReason(error.reason);
      return false;
    } catch (_) {
      errorMessage = messageForReason(null);
      return false;
    } finally {
      isSubmitting = false;
      _notify();
    }
  }

  void _clearSensitiveState() {
    fullName = email = driverTaxiStandName = driverTaxiStandAddress = '';
    vehiclePlate = vehicleBrand = vehicleModel = vehicleModelYear = '';
    selectedVehicleBrand = selectedVehicleModel = null;
    manualVehicleBrand = manualVehicleModel = '';
    isManualVehicleBrand = isManualVehicleModel = false;
    selectedVehicleModelYear = null;
    vehicleTaxiStandName = '';
    for (final type in uploadStates.keys) {
      uploadStates[type] = DriverApplicationUploadState.notSelected;
    }
  }

  static String messageForReason(String? reason) => switch (reason) {
    'invalid_full_name' => 'Ad ve soyad bilgisi geçerli değil.',
    'invalid_email' => 'E-posta adresi geçerli değil.',
    'invalid_taxi_stand_name' => 'Taksi durağı adı geçerli değil.',
    'invalid_taxi_stand_address' => 'Taksi durağı adresi geçerli değil.',
    'invalid_work_type' => 'Sürücü çalışma şekli geçerli değil.',
    'invalid_vehicle_plate' => 'Araç plakası geçerli değil.',
    'invalid_vehicle_brand' => 'Araç markası geçerli değil.',
    'invalid_vehicle_model' => 'Araç modeli geçerli değil.',
    'invalid_vehicle_model_year' => 'Araç model yılı geçerli değil.',
    'invalid_registration_owner_type' => 'Ruhsat sahibi bilgisi geçerli değil.',
    'vehicle_use_authorization_required' =>
      'Bu aracı kullanmaya yetkili olduğunuzu onaylamalısınız.',
    'required_declarations_not_accepted' =>
      'Zorunlu beyanların tamamını onaylamalısınız.',
    'verified_phone_required' =>
      'Doğrulanmış telefon numaranıza ulaşılamadı. Lütfen tekrar giriş yapın.',
    'driver_profile_exists' => 'Zaten bir sürücü profiliniz bulunuyor.',
    'driver_application_exists' =>
      'İncelenmekte olan bir sürücü başvurunuz bulunuyor.',
    'driver_application_already_approved' =>
      'Sürücü başvurunuz daha önce onaylandı.',
    'required_documents_missing' =>
      'Zorunlu belgelerden biri veya birkaçı yüklenmemiş.',
    'driver_application_document_invalid' =>
      'Yüklenen belgelerden biri doğrulanamadı.',
    'driver_application_document_copy_failed' =>
      'Belgeleriniz şu anda işlenemedi. Lütfen tekrar deneyin.',
    'driver_application_data_invalid' => 'Başvuru bilgileriniz doğrulanamadı.',
    'driver_application_persistence_failed' =>
      'Başvurunuz şu anda kaydedilemedi.',
    _ => 'Başvuru şu anda gönderilemedi. Lütfen tekrar deneyin.',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
