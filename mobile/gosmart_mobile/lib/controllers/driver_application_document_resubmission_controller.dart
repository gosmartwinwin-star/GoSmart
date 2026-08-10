import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../application/driver_application/driver_application_document_upload_gateway.dart';
import '../application/driver_application/driver_application_file_picker.dart';
import '../application/driver_application/driver_application_repository.dart';
import '../application/driver_application/resubmit_driver_application_gateway.dart';
import '../domain/driver_application/driver_application_document_type.dart';
import '../domain/driver_application/driver_application_review.dart';
import '../services/driver_application_review_service.dart';

enum DriverDocumentResubmissionUploadState {
  notSelected,
  selecting,
  uploading,
  uploaded,
  failed,
}

enum DriverDocumentResubmissionPickSource { camera, gallery, pdf }

class DriverApplicationDocumentResubmissionController extends ChangeNotifier {
  DriverApplicationDocumentResubmissionController({
    required DriverApplicationReview initialReview,
    required DriverApplicationRepository reviews,
    required DriverApplicationFilePicker picker,
    required DriverApplicationDocumentUploadGateway uploader,
    required ResubmitDriverApplicationGateway resubmitter,
    String Function()? requestIdGenerator,
  }) : review = initialReview,
       _reviews = reviews,
       _picker = picker,
       _uploader = uploader,
       _resubmitter = resubmitter,
       _requestIdGenerator = requestIdGenerator ?? _secureRequestId {
    _resetUploads();
  }

  final DriverApplicationRepository _reviews;
  final DriverApplicationFilePicker _picker;
  final DriverApplicationDocumentUploadGateway _uploader;
  final ResubmitDriverApplicationGateway _resubmitter;
  final String Function() _requestIdGenerator;

  DriverApplicationReview review;
  bool loading = false;
  bool submitting = false;
  bool submitted = false;
  String? errorMessage;
  String? _requestId;
  bool _uploadActive = false;
  bool _disposed = false;

  final Map<
    DriverApplicationDocumentType,
    DriverDocumentResubmissionUploadState
  >
  uploadStates = {};
  final Map<DriverApplicationDocumentType, PickedDriverApplicationFile>
  selectedFiles = {};
  final Map<DriverApplicationDocumentType, String> uploadErrors = {};

  List<DriverApplicationReviewDocument> get requiredDocuments =>
      review.requiredDocuments;
  bool isEditable(DriverApplicationDocumentType type) =>
      requiredDocuments.any((document) => document.type == type);
  bool get allRequiredUploaded =>
      requiredDocuments.isNotEmpty &&
      requiredDocuments.every(
        (document) =>
            uploadStates[document.type] ==
            DriverDocumentResubmissionUploadState.uploaded,
      );
  bool get canSubmit =>
      review.state ==
          DriverApplicationReviewState.awaitingDocumentResubmission &&
      allRequiredUploaded &&
      !submitting;

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    errorMessage = null;
    _notify();
    try {
      final latest = await _reviews.findForAuthenticatedUser();
      if (latest == null) {
        throw const FormatException('Başvuru bulunamadı.');
      }
      review = latest;
      _clearLocalUploads();
      _resetUploads();
    } on DriverApplicationReviewException catch (error) {
      errorMessage = messageForError(error);
    } catch (_) {
      errorMessage = 'Başvuru durumu yüklenemedi. Lütfen tekrar deneyin.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> pickAndUpload(
    DriverApplicationDocumentType type,
    DriverDocumentResubmissionPickSource source,
  ) async {
    if (!isEditable(type) || _uploadActive || submitting) return;
    _uploadActive = true;
    uploadStates[type] = DriverDocumentResubmissionUploadState.selecting;
    uploadErrors.remove(type);
    errorMessage = null;
    _notify();
    try {
      final file = switch (source) {
        DriverDocumentResubmissionPickSource.camera =>
          await _picker.pickFromCamera(documentType: type),
        DriverDocumentResubmissionPickSource.gallery =>
          await _picker.pickFromGallery(documentType: type),
        DriverDocumentResubmissionPickSource.pdf => await _picker.pickPdf(
          documentType: type,
        ),
      };
      if (file == null) {
        uploadStates[type] = DriverDocumentResubmissionUploadState.notSelected;
        return;
      }
      selectedFiles[type] = file;
      _requestId = null;
      uploadStates[type] = DriverDocumentResubmissionUploadState.uploading;
      _notify();
      await _uploader.upload(
        documentType: type,
        bytes: file.bytes,
        contentType: file.contentType,
      );
      uploadStates[type] = DriverDocumentResubmissionUploadState.uploaded;
    } on FormatException catch (error) {
      uploadStates[type] = DriverDocumentResubmissionUploadState.failed;
      uploadErrors[type] = error.message.contains('boyutu')
          ? 'Belge boyutu sınırı aşıldı.'
          : 'Bu dosya türü desteklenmiyor.';
    } catch (_) {
      uploadStates[type] = DriverDocumentResubmissionUploadState.failed;
      uploadErrors[type] = 'Belge yüklenemedi. Lütfen tekrar deneyin.';
    } finally {
      _uploadActive = false;
      _notify();
    }
  }

  Future<bool> submit() async {
    if (!canSubmit) return false;
    submitting = true;
    errorMessage = null;
    _requestId ??= _requestIdGenerator();
    _notify();
    try {
      await _resubmitter.resubmit(
        expectedSubmissionVersion: review.submissionVersion,
        requestId: _requestId!,
      );
      _clearLocalUploads();
      final latest = await _reviews.findForAuthenticatedUser();
      if (latest == null ||
          latest.state != DriverApplicationReviewState.pendingReview) {
        throw const FormatException('Başvuru durumu yenilenemedi.');
      }
      review = latest;
      _resetUploads();
      submitted = true;
      return true;
    } on DriverApplicationReviewException catch (error) {
      errorMessage = messageForError(error);
      if (error.reason == 'stale_driver_application_submission' ||
          error.reason == 'driver_application_not_awaiting_resubmission') {
        await _refreshAfterStale();
      }
      return false;
    } catch (_) {
      errorMessage = 'Belgeler yeniden gönderilemedi. Lütfen tekrar deneyin.';
      return false;
    } finally {
      submitting = false;
      _notify();
    }
  }

  Future<void> _refreshAfterStale() async {
    try {
      final latest = await _reviews.findForAuthenticatedUser();
      if (latest != null) review = latest;
    } catch (_) {
      // The controlled mutation error remains the user-facing message.
    }
  }

  void _clearLocalUploads() {
    selectedFiles.clear();
    uploadErrors.clear();
    uploadStates.clear();
    _requestId = null;
  }

  void _resetUploads() {
    for (final type in DriverApplicationDocumentType.values) {
      uploadStates[type] = DriverDocumentResubmissionUploadState.notSelected;
    }
  }

  static String messageForError(DriverApplicationReviewException error) =>
      switch (error.reason) {
        'stale_driver_application_submission' =>
          'Başvuru durumu değişti. Güncel bilgiler yeniden yüklendi.',
        'driver_application_not_awaiting_resubmission' =>
          'Başvurunuz artık belge yenileme beklemiyor.',
        'driver_application_no_documents_to_reupload' =>
          'Yenilenmesi gereken belge bulunamadı.',
        'driver_application_document_invalid' =>
          'Yüklenen belgelerden biri doğrulanamadı.',
        _ when error.code == 'unauthenticated' =>
          'Oturumunuz sona erdi. Lütfen tekrar giriş yapın.',
        _ when error.code == 'unavailable' =>
          'Bağlantı kurulamadı. Lütfen tekrar deneyin.',
        _ => 'İşlem tamamlanamadı. Lütfen tekrar deneyin.',
      };

  static String _secureRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clearLocalUploads();
    super.dispose();
  }
}
