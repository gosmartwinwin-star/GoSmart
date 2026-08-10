import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_document_upload_gateway.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_document_upload_result.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_file_picker.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_repository.dart';
import 'package:gosmart_mobile/application/driver_application/resubmit_driver_application_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_application_document_resubmission_controller.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_review.dart';
import 'package:gosmart_mobile/screens/driver/driver_application_document_resubmission_screen.dart';

void main() {
  final review = DriverApplicationReview(
    state: DriverApplicationReviewState.awaitingDocumentResubmission,
    submissionVersion: 2,
    documents: [
      for (final type in DriverApplicationDocumentType.values)
        DriverApplicationReviewDocument(
          type: type,
          status: switch (type.index) {
            0 || 4 => DriverApplicationPublicDocumentStatus.reuploadRequired,
            1 => DriverApplicationPublicDocumentStatus.approved,
            _ => DriverApplicationPublicDocumentStatus.pendingReview,
          },
          reuploadReason: type.index == 0 || type.index == 4
              ? DriverApplicationReuploadReason.informationMismatch
              : null,
        ),
    ],
  );

  DriverApplicationDocumentResubmissionController controller() =>
      DriverApplicationDocumentResubmissionController(
        initialReview: review,
        reviews: _Repository(review),
        picker: _Picker(),
        uploader: _Uploader(),
        resubmitter: _Resubmitter(),
        requestIdGenerator: () => 'request_123456789',
      );

  Future<void> show(
    WidgetTester tester,
    DriverApplicationDocumentResubmissionController value,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverApplicationDocumentResubmissionScreen(
          initialReview: review,
          controller: value,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('seven documents render without small viewport overflow', (
    tester,
  ) async {
    await show(tester, controller());
    for (final type in DriverApplicationDocumentType.values) {
      await tester.scrollUntilVisible(
        find.text(type.displayName),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text(type.displayName), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('only required documents have selection actions', (tester) async {
    await show(tester, controller());
    expect(find.text('Belge Seç'), findsAtLeastNWidgets(1));
    expect(find.text('Onaylandı'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(DriverApplicationDocumentType.vehicleRegistration.displayName),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Belge Seç'), findsAtLeastNWidgets(1));
  });

  testWidgets('controlled reason is visible and raw code is hidden', (
    tester,
  ) async {
    await show(tester, controller());
    expect(
      find.text('Belgedeki bilgiler başvuru bilgileriyle eşleşmiyor.'),
      findsOneWidget,
    );
    expect(find.text('information_mismatch'), findsNothing);
  });

  testWidgets('submit remains disabled until every required upload succeeds', (
    tester,
  ) async {
    final value = controller();
    await show(tester, value);
    await tester.scrollUntilVisible(
      find.text('Yeniden Gönder'),
      300,
      scrollable: find.byType(Scrollable),
    );
    FilledButton button() =>
        tester.widget(find.widgetWithText(FilledButton, 'Yeniden Gönder'));
    expect(button().onPressed, isNull);
    await value.pickAndUpload(
      DriverApplicationDocumentType.driverLicenseFront,
      DriverDocumentResubmissionPickSource.gallery,
    );
    await tester.pump();
    expect(button().onPressed, isNull);
    await value.pickAndUpload(
      DriverApplicationDocumentType.vehicleRegistration,
      DriverDocumentResubmissionPickSource.gallery,
    );
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });
}

class _Repository implements DriverApplicationRepository {
  _Repository(this.value);
  final DriverApplicationReview value;
  @override
  Future<DriverApplicationReview?> findForAuthenticatedUser() async => value;
}

class _Picker implements DriverApplicationFilePicker {
  PickedDriverApplicationFile get file => PickedDriverApplicationFile(
    bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
    contentType: 'image/jpeg',
  );
  @override
  Future<PickedDriverApplicationFile?> pickFromCamera({
    required documentType,
  }) async => file;
  @override
  Future<PickedDriverApplicationFile?> pickFromGallery({
    required documentType,
  }) async => file;
  @override
  Future<PickedDriverApplicationFile?> pickPdf({required documentType}) async =>
      file;
}

class _Uploader implements DriverApplicationDocumentUploadGateway {
  @override
  Future<DriverApplicationDocumentUploadResult> upload({
    required documentType,
    required bytes,
    required contentType,
  }) async => DriverApplicationDocumentUploadResult(
    documentType: documentType,
    storagePath: 'safe-test-path',
    contentType: contentType,
    sizeBytes: bytes.length,
    uploadedAt: DateTime.utc(2026),
  );
}

class _Resubmitter implements ResubmitDriverApplicationGateway {
  @override
  Future<int> resubmit({
    required expectedSubmissionVersion,
    required requestId,
  }) async => expectedSubmissionVersion + 1;
}
