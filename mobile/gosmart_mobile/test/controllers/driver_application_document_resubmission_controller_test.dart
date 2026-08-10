import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_document_upload_gateway.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_document_upload_result.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_file_picker.dart';
import 'package:gosmart_mobile/application/driver_application/driver_application_repository.dart';
import 'package:gosmart_mobile/application/driver_application/resubmit_driver_application_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_application_document_resubmission_controller.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_review.dart';
import 'package:gosmart_mobile/services/driver_application_review_service.dart';

void main() {
  DriverApplicationReview review({
    DriverApplicationReviewState state =
        DriverApplicationReviewState.awaitingDocumentResubmission,
    Set<DriverApplicationDocumentType> required = const {
      DriverApplicationDocumentType.driverLicenseFront,
    },
    int version = 2,
  }) => DriverApplicationReview(
    state: state,
    submissionVersion: version,
    documents: [
      for (final type in DriverApplicationDocumentType.values)
        DriverApplicationReviewDocument(
          type: type,
          status: required.contains(type)
              ? DriverApplicationPublicDocumentStatus.reuploadRequired
              : type == DriverApplicationDocumentType.driverLicenseBack
              ? DriverApplicationPublicDocumentStatus.approved
              : DriverApplicationPublicDocumentStatus.pendingReview,
          reuploadReason: required.contains(type)
              ? DriverApplicationReuploadReason.unreadableDocument
              : null,
        ),
    ],
  );

  DriverApplicationDocumentResubmissionController controller({
    DriverApplicationReview? initial,
    _Repository? repository,
    _Picker? picker,
    _Uploader? uploader,
    ResubmitDriverApplicationGateway? resubmitter,
  }) => DriverApplicationDocumentResubmissionController(
    initialReview: initial ?? review(),
    reviews:
        repository ??
        _Repository(
          review(state: DriverApplicationReviewState.pendingReview, version: 3),
        ),
    picker: picker ?? _Picker(),
    uploader: uploader ?? _Uploader(),
    resubmitter: resubmitter ?? _Resubmitter(),
    requestIdGenerator: () => 'request_123456789',
  );

  test('only reuploadRequired document is editable', () {
    final value = controller();
    expect(
      value.isEditable(DriverApplicationDocumentType.driverLicenseFront),
      isTrue,
    );
    expect(
      value.isEditable(DriverApplicationDocumentType.driverLicenseBack),
      isFalse,
    );
    expect(
      value.isEditable(DriverApplicationDocumentType.criminalRecord),
      isFalse,
    );
  });

  test('non-required document never opens picker or uploader', () async {
    final picker = _Picker();
    final uploader = _Uploader();
    final value = controller(picker: picker, uploader: uploader);
    await value.pickAndUpload(
      DriverApplicationDocumentType.driverLicenseBack,
      DriverDocumentResubmissionPickSource.gallery,
    );
    expect(picker.calls, 0);
    expect(uploader.calls, 0);
  });

  test(
    'required upload enables submit and retains other successful uploads',
    () async {
      final initial = review(
        required: {
          DriverApplicationDocumentType.driverLicenseFront,
          DriverApplicationDocumentType.identityCardBack,
        },
      );
      final value = controller(initial: initial);
      await value.pickAndUpload(
        DriverApplicationDocumentType.driverLicenseFront,
        DriverDocumentResubmissionPickSource.gallery,
      );
      expect(value.canSubmit, isFalse);
      await value.pickAndUpload(
        DriverApplicationDocumentType.identityCardBack,
        DriverDocumentResubmissionPickSource.camera,
      );
      expect(value.canSubmit, isTrue);
      expect(value.selectedFiles, hasLength(2));
    },
  );

  test('one upload failure does not clear another upload', () async {
    final uploader = _Uploader(
      failType: DriverApplicationDocumentType.identityCardBack,
    );
    final value = controller(
      initial: review(
        required: {
          DriverApplicationDocumentType.driverLicenseFront,
          DriverApplicationDocumentType.identityCardBack,
        },
      ),
      uploader: uploader,
    );
    await value.pickAndUpload(
      DriverApplicationDocumentType.driverLicenseFront,
      DriverDocumentResubmissionPickSource.gallery,
    );
    await value.pickAndUpload(
      DriverApplicationDocumentType.identityCardBack,
      DriverDocumentResubmissionPickSource.gallery,
    );
    expect(
      value.uploadStates[DriverApplicationDocumentType.driverLicenseFront],
      DriverDocumentResubmissionUploadState.uploaded,
    );
    expect(
      value.uploadStates[DriverApplicationDocumentType.identityCardBack],
      DriverDocumentResubmissionUploadState.failed,
    );
  });

  test('double submit is locked and requestId is stable for retry', () async {
    final submitter = _DeferredResubmitter();
    final value = controller(resubmitter: submitter);
    await value.pickAndUpload(
      DriverApplicationDocumentType.driverLicenseFront,
      DriverDocumentResubmissionPickSource.gallery,
    );
    final first = value.submit();
    await value.submit();
    expect(submitter.calls, 1);
    expect(submitter.requestIds.single, 'request_123456789');
    submitter.completeError(
      const DriverApplicationReviewException(code: 'unavailable'),
    );
    expect(await first, isFalse);
    await value.submit();
    expect(submitter.requestIds, everyElement('request_123456789'));
  });

  test('success clears local state and refreshes pendingReview', () async {
    final repository = _Repository(
      review(state: DriverApplicationReviewState.pendingReview, version: 3),
    );
    final value = controller(repository: repository);
    await value.pickAndUpload(
      DriverApplicationDocumentType.driverLicenseFront,
      DriverDocumentResubmissionPickSource.gallery,
    );
    expect(await value.submit(), isTrue);
    expect(value.submitted, isTrue);
    expect(value.review.state, DriverApplicationReviewState.pendingReview);
    expect(value.selectedFiles, isEmpty);
    expect(value.canSubmit, isFalse);
    expect(repository.calls, 1);
  });

  test('stale mutation is not retried and triggers one safe refresh', () async {
    final repository = _Repository(review(version: 4));
    final submitter = _Resubmitter(
      error: const DriverApplicationReviewException(
        code: 'failed-precondition',
        reason: 'stale_driver_application_submission',
      ),
    );
    final value = controller(repository: repository, resubmitter: submitter);
    await value.pickAndUpload(
      DriverApplicationDocumentType.driverLicenseFront,
      DriverDocumentResubmissionPickSource.gallery,
    );
    expect(await value.submit(), isFalse);
    expect(submitter.calls, 1);
    expect(repository.calls, 1);
    expect(value.review.submissionVersion, 4);
    expect(value.errorMessage, isNot(contains('stale_')));
  });
}

class _Repository implements DriverApplicationRepository {
  _Repository(this.value);
  final DriverApplicationReview? value;
  int calls = 0;
  @override
  Future<DriverApplicationReview?> findForAuthenticatedUser() async {
    calls++;
    return value;
  }
}

class _Picker implements DriverApplicationFilePicker {
  int calls = 0;
  PickedDriverApplicationFile get file => PickedDriverApplicationFile(
    bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
    contentType: 'image/jpeg',
  );
  @override
  Future<PickedDriverApplicationFile?> pickFromCamera({
    required documentType,
  }) async {
    calls++;
    return file;
  }

  @override
  Future<PickedDriverApplicationFile?> pickFromGallery({
    required documentType,
  }) async {
    calls++;
    return file;
  }

  @override
  Future<PickedDriverApplicationFile?> pickPdf({required documentType}) async {
    calls++;
    return file;
  }
}

class _Uploader implements DriverApplicationDocumentUploadGateway {
  _Uploader({this.failType});
  final DriverApplicationDocumentType? failType;
  int calls = 0;
  @override
  Future<DriverApplicationDocumentUploadResult> upload({
    required documentType,
    required bytes,
    required contentType,
  }) async {
    calls++;
    if (documentType == failType) throw StateError('failed');
    return DriverApplicationDocumentUploadResult(
      documentType: documentType,
      storagePath: 'safe-test-path',
      contentType: contentType,
      sizeBytes: bytes.length,
      uploadedAt: DateTime.utc(2026),
    );
  }
}

class _Resubmitter implements ResubmitDriverApplicationGateway {
  _Resubmitter({this.error});
  final Object? error;
  int calls = 0;
  @override
  Future<int> resubmit({
    required expectedSubmissionVersion,
    required requestId,
  }) async {
    calls++;
    if (error != null) throw error!;
    return expectedSubmissionVersion + 1;
  }
}

class _DeferredResubmitter implements ResubmitDriverApplicationGateway {
  int calls = 0;
  final requestIds = <String>[];
  Completer<int> completer = Completer<int>();
  Object? nextError;
  @override
  Future<int> resubmit({
    required expectedSubmissionVersion,
    required requestId,
  }) {
    calls++;
    requestIds.add(requestId);
    if (nextError != null) return Future<int>.error(nextError!);
    return completer.future;
  }

  void completeError(Object error) {
    completer.completeError(error);
    nextError = error;
  }
}
