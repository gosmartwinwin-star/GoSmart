import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../application/driver_application/submit_driver_application_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import '../domain/driver_application/driver_work_type.dart';
import '../domain/driver_application/registration_owner_type.dart';

class SubmitDriverApplicationException implements Exception {
  final String code;
  final String? reason;
  const SubmitDriverApplicationException({required this.code, this.reason});
}

abstract interface class SubmitDriverApplicationAuthSession {
  Future<void> requireAuthenticatedUser();
}

abstract interface class SubmitDriverApplicationCallableInvoker {
  Future<Object?> call(Map<String, Object?> payload);
}

class FirebaseSubmitDriverApplicationAuthSession
    implements SubmitDriverApplicationAuthSession {
  final FirebaseAuth _auth;
  FirebaseSubmitDriverApplicationAuthSession({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;
  @override
  Future<void> requireAuthenticatedUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const SubmitDriverApplicationException(code: 'unauthenticated');
    }
    try {
      await user.getIdToken(true);
    } on FirebaseAuthException {
      throw const SubmitDriverApplicationException(code: 'unauthenticated');
    }
  }
}

class FirebaseSubmitDriverApplicationCallableInvoker
    implements SubmitDriverApplicationCallableInvoker {
  final FirebaseFunctions _functions;
  FirebaseSubmitDriverApplicationCallableInvoker({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctionsRegistry.client;
  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      return (await _functions
              .httpsCallable('submitDriverApplication')
              .call(payload))
          .data;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      throw SubmitDriverApplicationException(
        code: error.code,
        reason: details is Map && details['reason'] is String
            ? details['reason'] as String
            : null,
      );
    }
  }
}

class SubmitDriverApplicationService implements SubmitDriverApplicationGateway {
  final SubmitDriverApplicationAuthSession _auth;
  final SubmitDriverApplicationCallableInvoker _invoker;
  SubmitDriverApplicationService({
    SubmitDriverApplicationAuthSession? auth,
    SubmitDriverApplicationCallableInvoker? invoker,
  }) : _auth = auth ?? FirebaseSubmitDriverApplicationAuthSession(),
       _invoker = invoker ?? FirebaseSubmitDriverApplicationCallableInvoker();

  @override
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
  }) async {
    await _auth.requireAuthenticatedUser();
    final payload = <String, Object?>{
      'fullName': fullName,
      'workType': workType.name,
      'vehiclePlate': vehiclePlate,
      'vehicleBrand': vehicleBrand,
      'vehicleModel': vehicleModel,
      'vehicleModelYear': vehicleModelYear,
      'registrationOwnerType': registrationOwnerType.name,
      'hasVehicleUseAuthorization': hasVehicleUseAuthorization,
      'informationAccuracyAccepted': informationAccuracyAccepted,
      'documentValidityNotificationAccepted':
          documentValidityNotificationAccepted,
      'documentProcessingNoticeAccepted': documentProcessingNoticeAccepted,
      'kvkkNoticeAccepted': kvkkNoticeAccepted,
      'termsAccepted': termsAccepted,
      'marketingConsent': marketingConsent,
    };
    void optional(String key, String? value) {
      final normalized = value?.trim();
      if (normalized?.isNotEmpty == true) payload[key] = normalized;
    }

    optional('email', email);
    optional('driverTaxiStandName', driverTaxiStandName);
    optional('driverTaxiStandAddress', driverTaxiStandAddress);
    optional('vehicleTaxiStandName', vehicleTaxiStandName);
    final response = await _invoker.call(payload);
    if (response is! Map || response['status'] != 'pendingReview') {
      throw const FormatException('Başvuru yanıtı geçersiz.');
    }
    final submitted = response['submittedAtMillis'];
    final updated = response['updatedAtMillis'];
    final version = response['submissionVersion'];
    if (submitted is! int ||
        submitted < 0 ||
        updated is! int ||
        updated < submitted ||
        version is! int ||
        version <= 0) {
      throw const FormatException('Başvuru yanıtı geçersiz.');
    }
    return SubmittedDriverApplication(
      submittedAt: DateTime.fromMillisecondsSinceEpoch(submitted, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updated, isUtc: true),
      submissionVersion: version,
    );
  }
}
