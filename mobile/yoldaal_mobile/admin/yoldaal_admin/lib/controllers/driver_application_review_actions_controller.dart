import 'dart:async';
// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';
import '../application/ports.dart';
import '../core/admin_exceptions.dart';
import '../domain/driver_application.dart';

final class DriverApplicationReviewActionsController extends ChangeNotifier {
  DriverApplicationReviewActionsController({
    required DriverApplicationAdminReviewGateway gateway,
    required Future<void> Function() refreshDetails,
    required Future<void> Function() refreshList,
    required Future<void> Function() refreshTimeline,
    required VoidCallback invalidateReviewContext,
    required VoidCallback clearDetails,
    required Future<void> Function() handleAuthFailure,
    DateTime Function()? now,
  }) : _gateway = gateway,
       _refreshDetails = refreshDetails,
       _refreshList = refreshList,
       _refreshTimeline = refreshTimeline,
       _invalidateReviewContext = invalidateReviewContext,
       _clearDetails = clearDetails,
       _handleAuthFailure = handleAuthFailure,
       _now = now ?? DateTime.now;

  final DriverApplicationAdminReviewGateway _gateway;
  final Future<void> Function() _refreshDetails;
  final Future<void> Function() _refreshList;
  final Future<void> Function() _refreshTimeline;
  final VoidCallback _invalidateReviewContext;
  final VoidCallback _clearDetails;
  final Future<void> Function() _handleAuthFailure;
  final DateTime Function() _now;
  DriverApplicationDocumentPreview? activePreview;
  DriverDocumentType? activeDocumentType;
  bool isLoadingPreview = false;
  bool isSubmittingDocumentDecision = false;
  bool isSubmittingApplicationDecision = false;
  String? previewErrorMessage;
  String? actionErrorMessage;
  String? successMessage;
  bool _disposed = false;
  Timer? _expiryTimer;

  Future<void> openDocumentPreview({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
  }) async {
    if (_disposed || isLoadingPreview) return;
    closeDocumentPreview();
    activeDocumentType = documentType;
    isLoadingPreview = true;
    previewErrorMessage = null;
    _notify();
    try {
      final preview = await _gateway.createDocumentPreview(
        applicationId: applicationId,
        reviewContext: reviewContext,
        documentType: documentType,
      );
      if (!preview.isReusableAt(_now())) {
        throw const FormatException('Expired preview');
      }
      activePreview = preview;
      final delay =
          preview.expiresAt.difference(_now().toUtc()) -
          const Duration(seconds: 15);
      _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
        closeDocumentPreview();
        previewErrorMessage = 'Belge erişiminin süresi doldu.';
        _notify();
      });
    } catch (error) {
      activePreview = null;
      previewErrorMessage = adminPanelMessage(error);
      await _handleSpecialError(error);
    } finally {
      isLoadingPreview = false;
      _notify();
    }
  }

  void closeDocumentPreview() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    activePreview = null;
    activeDocumentType = null;
    _notify();
  }

  Future<bool> approveDocument({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
  }) => _documentAction(
    () => _gateway.approveDocument(
      applicationId: applicationId,
      reviewContext: reviewContext,
      documentType: documentType,
    ),
    'Belge kararı kaydedildi.',
  );

  Future<bool> requestDocumentReupload({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
    required DriverDocumentReuploadReason reason,
  }) => _documentAction(
    () => _gateway.requestDocumentReupload(
      applicationId: applicationId,
      reviewContext: reviewContext,
      documentType: documentType,
      reason: reason,
    ),
    'Belgenin yeniden yüklenmesi istendi.',
  );

  Future<bool> _documentAction(
    Future<void> Function() mutation,
    String message,
  ) async {
    if (_disposed ||
        isSubmittingDocumentDecision ||
        isSubmittingApplicationDecision) {
      return false;
    }
    isSubmittingDocumentDecision = true;
    actionErrorMessage = null;
    successMessage = null;
    _notify();
    try {
      await mutation();
      successMessage = message;
      await _refreshAfterMutation();
      return true;
    } catch (error) {
      actionErrorMessage = adminPanelMessage(error);
      await _handleSpecialError(error);
      return false;
    } finally {
      isSubmittingDocumentDecision = false;
      _notify();
    }
  }

  Future<bool> approveApplication({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
  }) => _applicationAction(
    () => _gateway.approveApplication(
      applicationId: applicationId,
      reviewContext: reviewContext,
    ),
    'Sürücü başvurusu onaylandı.',
  );

  Future<bool> rejectApplication({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverApplicationRejectionReason reason,
  }) => _applicationAction(
    () => _gateway.rejectApplication(
      applicationId: applicationId,
      reviewContext: reviewContext,
      reason: reason,
    ),
    'Sürücü başvurusu reddedildi.',
  );

  Future<bool> _applicationAction(
    Future<void> Function() mutation,
    String message,
  ) async {
    if (_disposed ||
        isSubmittingApplicationDecision ||
        isSubmittingDocumentDecision) {
      return false;
    }
    isSubmittingApplicationDecision = true;
    actionErrorMessage = null;
    successMessage = null;
    _notify();
    try {
      await mutation();
      successMessage = message;
      await _refreshAfterMutation();
      return true;
    } catch (error) {
      actionErrorMessage = adminPanelMessage(error);
      await _handleSpecialError(error);
      return false;
    } finally {
      isSubmittingApplicationDecision = false;
      _notify();
    }
  }

  Future<void> _refreshAfterMutation() async {
    closeDocumentPreview();
    _invalidateReviewContext();
    await Future.wait([_refreshDetails(), _refreshList(), _refreshTimeline()]);
  }

  Future<void> _handleSpecialError(Object error) async {
    if (error is! AdminPanelException) return;
    if (error.reason == 'stale_driver_application_review') {
      actionErrorMessage =
          'Başvuru siz incelerken güncellendi. Güncel bilgiler yeniden yükleniyor.';
      closeDocumentPreview();
      _invalidateReviewContext();
      await Future.wait([
        _refreshDetails(),
        _refreshList(),
        _refreshTimeline(),
      ]);
    } else if (const {
          'authentication_required',
          'session_expired',
          'admin_access_required',
        }.contains(error.reason) ||
        const {'unauthenticated', 'permission-denied'}.contains(error.code)) {
      clearSensitiveState();
      _clearDetails();
      await _handleAuthFailure();
    }
  }

  void clearSensitiveState() {
    closeDocumentPreview();
    previewErrorMessage = null;
    actionErrorMessage = null;
    successMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  String toString() =>
      'DriverApplicationReviewActionsController(preview: [REDACTED])';
  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    activePreview = null;
    super.dispose();
  }
}
