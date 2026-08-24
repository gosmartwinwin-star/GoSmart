import 'package:flutter/foundation.dart';
import '../application/ports.dart';
import '../core/admin_exceptions.dart';
import '../domain/driver_application_review_event.dart';

final class DriverApplicationReviewEventsController extends ChangeNotifier {
  DriverApplicationReviewEventsController(
    this._gateway, {
    Future<void> Function()? handleAuthFailure,
  }) : _handleAuthFailure = handleAuthFailure ?? _noOp;
  final DriverApplicationReviewEventsGateway _gateway;
  final Future<void> Function() _handleAuthFailure;
  String? currentApplicationId;
  List<DriverApplicationReviewEvent> items = const [];
  DriverApplicationReviewEventsCursor? nextCursor;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? errorMessage;
  bool _disposed = false;
  int _generation = 0;

  static Future<void> _noOp() async {}

  Future<void> loadInitial(String applicationId) async {
    if (_disposed || (isLoading && currentApplicationId == applicationId)) {
      return;
    }
    if (currentApplicationId != applicationId) clearSensitiveState();
    final generation = ++_generation;
    currentApplicationId = applicationId;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final page = await _gateway.listReviewEvents(
        applicationId: applicationId,
      );
      if (_disposed ||
          currentApplicationId != applicationId ||
          generation != _generation) {
        return;
      }
      items = page.items;
      nextCursor = page.nextCursor;
    } catch (error) {
      if (currentApplicationId == applicationId && generation == _generation) {
        items = const [];
        nextCursor = null;
        errorMessage = adminPanelMessage(error);
      }
      await _handleAuthError(error);
    } finally {
      if (generation == _generation) {
        isLoading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final id = currentApplicationId;
    final cursor = nextCursor;
    if (_disposed ||
        id == null ||
        cursor == null ||
        isLoading ||
        isLoadingMore) {
      return;
    }
    isLoadingMore = true;
    errorMessage = null;
    _notify();
    try {
      final page = await _gateway.listReviewEvents(
        applicationId: id,
        cursor: cursor,
      );
      if (_disposed || currentApplicationId != id) return;
      final keys = items.map((item) => item.safeKey).toSet();
      items = [...items, ...page.items.where((item) => keys.add(item.safeKey))];
      nextCursor = page.nextCursor;
    } catch (error) {
      errorMessage = adminPanelMessage(error);
      await _handleAuthError(error);
    } finally {
      isLoadingMore = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    final id = currentApplicationId;
    if (id != null) await loadInitial(id);
  }

  Future<void> _handleAuthError(Object error) async {
    if (error is AdminPanelException &&
        (const {
              'authentication_required',
              'session_expired',
              'admin_access_required',
            }.contains(error.reason) ||
            const {
              'unauthenticated',
              'permission-denied',
            }.contains(error.code))) {
      clearSensitiveState();
      await _handleAuthFailure();
    }
  }

  void clearSensitiveState() {
    _generation++;
    currentApplicationId = null;
    items = const [];
    nextCursor = null;
    errorMessage = null;
    isLoading = false;
    isLoadingMore = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  String toString() => 'DriverApplicationReviewEventsController(redacted)';
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    currentApplicationId = null;
    items = const [];
    nextCursor = null;
    super.dispose();
  }
}
