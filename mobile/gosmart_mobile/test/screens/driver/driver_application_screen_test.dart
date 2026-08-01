import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_document_upload_gateway.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_document_upload_result.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_file_picker.dart';
import 'package:gosmart_mobile/application/driver_application/submit_driver_application_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_application_form_controller.dart';
import 'package:gosmart_mobile/core/branding/gosmart_slogans.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';
import 'package:gosmart_mobile/screens/driver/driver_application_screen.dart';

class Info implements DriverApplicationUserInfoProvider {
  @override
  String? get verifiedPhoneNumber => '+905000000000';
}

class Picker implements DriverApplicationFilePicker {
  @override
  Future<PickedDriverApplicationFile?> pickFromCamera({
    required documentType,
  }) async => null;
  @override
  Future<PickedDriverApplicationFile?> pickFromGallery({
    required documentType,
  }) async => null;
  @override
  Future<PickedDriverApplicationFile?> pickPdf({required documentType}) async =>
      null;
}

class Uploader implements DriverApplicationDocumentUploadGateway {
  @override
  Future<DriverApplicationDocumentUploadResult> upload({
    required documentType,
    required Uint8List bytes,
    required String contentType,
  }) => throw UnimplementedError();
}

class Submitter implements SubmitDriverApplicationGateway {
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
  }) => throw UnimplementedError();
}

DriverApplicationFormController controller() => DriverApplicationFormController(
  picker: Picker(),
  uploader: Uploader(),
  submitter: Submitter(),
  userInfo: Info(),
);
Future<void> show(WidgetTester tester, DriverApplicationFormController value) =>
    tester.pumpWidget(
      MaterialApp(home: DriverApplicationScreen(controller: value)),
    );

void main() {
  testWidgets('başlık slogan ve dört aşama görünür', (tester) async {
    await show(tester, controller());
    expect(find.text('Sürücü Başvurusu'), findsOneWidget);
    expect(find.text(GoSmartSlogans.driver), findsOneWidget);
    for (final label in ['Kişisel', 'Araç', 'Belgeler', 'Onay']) {
      expect(find.text(label), findsOneWidget);
    }
  });
  testWidgets('telefon salt okunur, UID ve çalışma şehri görünmez', (
    tester,
  ) async {
    await show(tester, controller());
    expect(find.text('+905000000000'), findsOneWidget);
    expect(find.textContaining('user-'), findsNothing);
    expect(find.textContaining('Çalışma Şehri'), findsNothing);
    final phone = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField),
        matching: find.byType(EditableText),
      ),
    );
    expect(phone.readOnly, isTrue);
  });
  testWidgets('belgeler adımında yedi belge kartı görünür', (tester) async {
    final value = controller()..currentStep = 2;
    await show(tester, value);
    for (final type in DriverApplicationDocumentType.values) {
      expect(find.text(type.displayName), findsOneWidget);
    }
    expect(find.text('PDF Seç'), findsNothing);
  });
  testWidgets('onay adımında beyanlar ve taslak hukuk uyarısı görünür', (
    tester,
  ) async {
    final value = controller()..currentStep = 3;
    await show(tester, value);
    expect(find.textContaining('Pazarlama iletişimine'), findsOneWidget);
    expect(find.textContaining('Taslak metin'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(6));
  });
}
