import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_work_type.dart';
import 'package:gosmart_mobile/domain/driver_application/registration_owner_type.dart';
import 'package:gosmart_mobile/services/submit_driver_application_service.dart';

class Auth implements SubmitDriverApplicationAuthSession {
  final bool valid;
  Auth(this.valid);
  @override
  Future<void> requireAuthenticatedUser() async {
    if (!valid)
      throw const SubmitDriverApplicationException(code: 'unauthenticated');
  }
}

class Invoker implements SubmitDriverApplicationCallableInvoker {
  int calls = 0;
  Map<String, Object?>? payload;
  Object? response = {
    'status': 'pendingReview',
    'submittedAtMillis': 1000,
    'updatedAtMillis': 1001,
    'submissionVersion': 1,
  };
  Object? error;
  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    calls++;
    this.payload = payload;
    if (error != null) throw error!;
    return response;
  }
}

Future<dynamic> submit(Invoker invoker, {bool auth = true}) =>
    SubmitDriverApplicationService(auth: Auth(auth), invoker: invoker).submit(
      fullName: 'Ali Veli',
      email: '  ',
      driverTaxiStandName: null,
      driverTaxiStandAddress: '',
      workType: DriverWorkType.vehicleOwner,
      vehiclePlate: '06 ABC 123',
      vehicleBrand: 'Fiat',
      vehicleModel: 'Egea',
      vehicleModelYear: 2020,
      registrationOwnerType: RegistrationOwnerType.applicant,
      hasVehicleUseAuthorization: false,
      vehicleTaxiStandName: '',
      informationAccuracyAccepted: true,
      documentValidityNotificationAccepted: true,
      documentProcessingNoticeAccepted: true,
      kvkkNoticeAccepted: true,
      termsAccepted: true,
      marketingConsent: false,
    );

void main() {
  test('payload yalnız izin verilen alanları taşır', () async {
    final invoker = Invoker();
    await submit(invoker);
    expect(invoker.payload, containsPair('workType', 'vehicleOwner'));
    expect(invoker.payload, containsPair('registrationOwnerType', 'applicant'));
    expect(invoker.payload, containsPair('marketingConsent', false));
    for (final forbidden in [
      'authUserId',
      'phoneNumber',
      'verifiedPhoneNumber',
      'serviceCity',
      'status',
      'documents',
      'storagePath',
      'documentSetId',
      'submittedAt',
      'updatedAt',
    ]) {
      expect(invoker.payload, isNot(contains(forbidden)));
    }
    expect(invoker.payload, isNot(contains('email')));
  });

  test('geçerli response UTC zamanlarla parse edilir', () async {
    final result = await submit(Invoker());
    expect(result.submittedAt.isUtc, isTrue);
    expect(result.updatedAt.isUtc, isTrue);
    expect(result.submissionVersion, 1);
  });

  for (final response in [
    {
      'status': 'pendingReview',
      'submittedAtMillis': 1.0,
      'updatedAtMillis': 2,
      'submissionVersion': 1,
    },
    {
      'status': 'pendingReview',
      'submittedAtMillis': 1,
      'updatedAtMillis': true,
      'submissionVersion': 1,
    },
    {
      'status': 'approved',
      'submittedAtMillis': 1,
      'updatedAtMillis': 2,
      'submissionVersion': 1,
    },
  ]) {
    test('geçersiz response reddedilir', () async {
      final invoker = Invoker()..response = response;
      await expectLater(submit(invoker), throwsFormatException);
    });
  }

  test('backend reason korunur', () async {
    final invoker = Invoker()
      ..error = const SubmitDriverApplicationException(
        code: 'failed-precondition',
        reason: 'required_documents_missing',
      );
    await expectLater(
      submit(invoker),
      throwsA(isA<SubmitDriverApplicationException>()),
    );
  });

  test('auth yoksa callable çağrılmaz', () async {
    final invoker = Invoker();
    await expectLater(
      submit(invoker, auth: false),
      throwsA(isA<SubmitDriverApplicationException>()),
    );
    expect(invoker.calls, 0);
  });
}
