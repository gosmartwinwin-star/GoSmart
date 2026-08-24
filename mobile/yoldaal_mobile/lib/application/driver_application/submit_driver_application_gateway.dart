import '../../domain/driver_application/driver_work_type.dart';
import '../../domain/driver_application/registration_owner_type.dart';

class SubmittedDriverApplication {
  final DateTime submittedAt;
  final DateTime updatedAt;
  final int submissionVersion;

  const SubmittedDriverApplication({
    required this.submittedAt,
    required this.updatedAt,
    required this.submissionVersion,
  });
}

abstract interface class SubmitDriverApplicationGateway {
  Future<SubmittedDriverApplication> submit({
    required String fullName,
    String? email,
    String? driverTaxiStandName,
    String? driverTaxiStandAddress,
    required DriverWorkType workType,
    required String vehiclePlate,
    required String vehicleBrand,
    required String vehicleModel,
    required int vehicleModelYear,
    required RegistrationOwnerType registrationOwnerType,
    required bool hasVehicleUseAuthorization,
    String? vehicleTaxiStandName,
    required bool informationAccuracyAccepted,
    required bool documentValidityNotificationAccepted,
    required bool documentProcessingNoticeAccepted,
    required bool kvkkNoticeAccepted,
    required bool termsAccepted,
    required bool marketingConsent,
  });
}
