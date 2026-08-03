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
  DriverApplicationDetailsController(this._gateway);
  final DriverApplicationAdminReadGateway _gateway;
  DriverApplicationReviewDetails? details;
  bool isLoading = false;
  String? errorMessage;
  String? _applicationId;
  bool _disposed = false;

  Future<void> load(String applicationId) async {
    if (_disposed || isLoading) return;
    if (_applicationId != applicationId) details = null;
    _applicationId = applicationId;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      details = await _gateway.getDetails(applicationId: applicationId);
    } catch (error) {
      details = null;
      errorMessage = adminPanelMessage(error);
    } finally {
      isLoading = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    final id = _applicationId;
    if (id != null) {
      details = null;
      await load(id);
    }
  }

  void clearSensitiveState() {
    details = null;
    _applicationId = null;
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
