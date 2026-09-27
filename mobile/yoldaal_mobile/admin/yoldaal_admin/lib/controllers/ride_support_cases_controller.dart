import 'package:flutter/foundation.dart';
import '../application/ride_support_admin_ports.dart';
import '../core/admin_exceptions.dart';
import '../domain/ride_support_case.dart';

final class RideSupportCasesController extends ChangeNotifier {
  RideSupportCasesController(
    this._gateway, {
    Future<void> Function()? handleAuthFailure,
  }) : _handleAuthFailure = handleAuthFailure ?? _noOp;

  final RideSupportAdminReadGateway _gateway;
  final Future<void> Function() _handleAuthFailure;
  List<RideSupportCaseSummary> items = const [];
  RideSupportCaseCursor? nextCursor;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? errorMessage;
  bool _disposed = false;

  static Future<void> _noOp() async {}

  Future<void> loadInitial() async {
    if (_disposed || isLoading) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final page = await _gateway.list();
      items = page.items;
      nextCursor = page.nextCursor;
    } catch (error) {
      items = const [];
      nextCursor = null;
      errorMessage = adminPanelMessage(error);
      await _handleAuthError(error);
    } finally {
      isLoading = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    items = const [];
    nextCursor = null;
    await loadInitial();
  }

  Future<void> loadMore() async {
    final cursor = nextCursor;
    if (_disposed || isLoading || isLoadingMore || cursor == null) return;
    isLoadingMore = true;
    errorMessage = null;
    _notify();
    try {
      final page = await _gateway.list(cursor: cursor);
      final keys = items.map((item) => '${item.rideId}/${item.caseId}').toSet();
      items = [
        ...items,
        ...page.items.where(
          (item) => keys.add('${item.rideId}/${item.caseId}'),
        ),
      ];
      nextCursor = page.nextCursor;
    } catch (error) {
      errorMessage = adminPanelMessage(error);
      await _handleAuthError(error);
    } finally {
      isLoadingMore = false;
      _notify();
    }
  }

  Future<void> _handleAuthError(Object error) async {
    if (error is AdminPanelException &&
        (const {
              'authentication_required',
              'session_expired',
              'admin_access_required',
            }.contains(error.reason) ||
            const {'unauthenticated', 'permission-denied'}.contains(error.code))) {
      clearSensitiveState();
      await _handleAuthFailure();
    }
  }

  void clearSensitiveState() {
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
  void dispose() {
    _disposed = true;
    items = const [];
    nextCursor = null;
    super.dispose();
  }
}
