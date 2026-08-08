import 'package:flutter/foundation.dart';
import '../application/ports.dart';
import '../core/admin_exceptions.dart';
import '../domain/driver_application.dart';

final class DriverApplicationsController extends ChangeNotifier {
  DriverApplicationsController(this._gateway);
  final DriverApplicationAdminReadGateway _gateway;
  DriverApplicationReviewStatus selectedStatus =
      DriverApplicationReviewStatus.pendingReview;
  List<DriverApplicationReviewSummary> items = const [];
  DriverApplicationReviewCursor? nextCursor;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? errorMessage;
  bool _disposed = false;

  Future<void> loadInitial() async {
    if (_disposed || isLoading) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final page = await _gateway.list(status: selectedStatus);
      items = page.items;
      nextCursor = page.nextCursor;
    } catch (error) {
      errorMessage = adminPanelMessage(error);
    } finally {
      isLoading = false;
      _notify();
    }
  }

  Future<void> changeStatus(DriverApplicationReviewStatus status) async {
    if (selectedStatus == status) return;
    selectedStatus = status;
    items = const [];
    nextCursor = null;
    errorMessage = null;
    _notify();
    await loadInitial();
  }

  Future<void> loadMore() async {
    final cursor = nextCursor;
    if (_disposed || isLoadingMore || cursor == null) return;
    isLoadingMore = true;
    errorMessage = null;
    _notify();
    try {
      final page = await _gateway.list(status: selectedStatus, cursor: cursor);
      final ids = items.map((item) => item.applicationId).toSet();
      items = [
        ...items,
        ...page.items.where((item) => ids.add(item.applicationId)),
      ];
      nextCursor = page.nextCursor;
    } catch (error) {
      errorMessage = adminPanelMessage(error);
    } finally {
      isLoadingMore = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    items = const [];
    nextCursor = null;
    await loadInitial();
  }

  void clearSensitiveState() {
    items = const [];
    nextCursor = null;
    errorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class DriverApplicationDetailsController extends ChangeNotifier {
  DriverApplicationDetailsController(
    this._gateway, {
    Future<void> Function()? handleAuthFailure,
  }) : _handleAuthFailure = handleAuthFailure ?? _noOp;
  final DriverApplicationAdminReadGateway _gateway;
  final Future<void> Function() _handleAuthFailure;
  String? currentApplicationId;
  DriverApplicationReviewDetails? details;
  bool isLoading = false;
  bool isRefreshing = false;
  String? errorMessage;
  bool hasFreshMutationContext = false;
  bool _disposed = false;
  int _generation = 0;

  static Future<void> _noOp() async {}

  Future<void> load(String applicationId) async {
    if (_disposed || (isLoading && currentApplicationId == applicationId)) {
      return;
    }
    if (currentApplicationId != applicationId) {
      _generation++;
      details = null;
      hasFreshMutationContext = false;
    }
    currentApplicationId = applicationId;
    final generation = _generation;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final loaded = await _gateway.getDetails(applicationId: applicationId);
      if (_disposed ||
          generation != _generation ||
          currentApplicationId != applicationId) {
        return;
      }
      details = loaded;
      hasFreshMutationContext = true;
    } catch (error) {
      if (generation == _generation && currentApplicationId == applicationId) {
        if (_isAuthError(error)) {
          clearSensitiveState();
          await _handleAuthFailure();
        } else {
          details = null;
          hasFreshMutationContext = false;
          errorMessage = adminPanelMessage(error);
        }
      }
    } finally {
      if (generation == _generation) {
        isLoading = false;
        _notify();
      }
    }
  }

  Future<void> refresh() async {
    final id = currentApplicationId;
    if (_disposed || id == null || isLoading || isRefreshing) return;
    final generation = _generation;
    isRefreshing = true;
    hasFreshMutationContext = false;
    errorMessage = null;
    _notify();
    try {
      final loaded = await _gateway.getDetails(applicationId: id);
      if (_disposed ||
          generation != _generation ||
          currentApplicationId != id) {
        return;
      }
      details = loaded;
      hasFreshMutationContext = true;
    } catch (error) {
      if (generation == _generation && currentApplicationId == id) {
        if (_isAuthError(error)) {
          clearSensitiveState();
          await _handleAuthFailure();
        } else {
          hasFreshMutationContext = false;
          errorMessage = details == null
              ? 'Başvuru ayrıntıları yüklenemedi.'
              : 'İşlem kaydedildi ancak güncel başvuru bilgileri yüklenemedi.';
        }
      }
    } finally {
      if (generation == _generation) {
        isRefreshing = false;
        _notify();
      }
    }
  }

  void invalidateReviewContext() {
    hasFreshMutationContext = false;
    _notify();
  }

  bool _isAuthError(Object error) =>
      error is AdminPanelException &&
      (const {
            'authentication_required',
            'session_expired',
            'admin_access_required',
          }.contains(error.reason) ||
          const {'unauthenticated', 'permission-denied'}.contains(error.code));

  void clearSensitiveState() {
    _generation++;
    details = null;
    currentApplicationId = null;
    hasFreshMutationContext = false;
    isLoading = false;
    isRefreshing = false;
    errorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    details = null;
    currentApplicationId = null;
    hasFreshMutationContext = false;
    super.dispose();
  }
}
