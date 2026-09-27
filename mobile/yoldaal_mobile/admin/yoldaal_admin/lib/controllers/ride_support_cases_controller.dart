import 'dart:math';

import 'package:flutter/foundation.dart';
import '../application/ride_support_admin_ports.dart';
import '../core/admin_exceptions.dart';
import '../domain/ride_support_case.dart';

final class RideSupportCasesController extends ChangeNotifier {
  RideSupportCasesController(
    this._gateway, {
    Future<void> Function()? handleAuthFailure,
    String Function()? requestIdFactory,
  }) : _handleAuthFailure = handleAuthFailure ?? _noOp,
       _requestIdFactory = requestIdFactory ?? _secureRequestId;

  final RideSupportAdminReadGateway _gateway;
  final Future<void> Function() _handleAuthFailure;
  final String Function() _requestIdFactory;
  List<RideSupportCaseSummary> items = const [];
  RideSupportCaseCursor? nextCursor;
  bool isLoading = false;
  bool isLoadingMore = false;
  bool isMutating = false;
  String? errorMessage;
  String? actionErrorMessage;
  bool _disposed = false;

  static final Random _random = Random.secure();

  static Future<void> _noOp() async {}

  static String _secureRequestId() => List<String>.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    growable: false,
  ).join();

  bool get supportsTransitions => _gateway is RideSupportAdminTransitionGateway;

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

  Future<bool> advanceStatus(RideSupportCaseSummary item) async {
    final targetStatus = item.status.nextStatus;
    final transitionGateway = _gateway is RideSupportAdminTransitionGateway
        ? _gateway as RideSupportAdminTransitionGateway
        : null;
    if (_disposed ||
        isMutating ||
        targetStatus == null ||
        transitionGateway is! RideSupportAdminTransitionGateway) {
      return false;
    }

    isMutating = true;
    actionErrorMessage = null;
    _notify();
    try {
      await transitionGateway.transition(
        rideId: item.rideId,
        caseId: item.caseId,
        targetStatus: targetStatus,
        expectedUpdatedAt: item.updatedAt,
        requestId: _requestIdFactory(),
      );
      await refresh();
      return true;
    } catch (error) {
      if (error is AdminPanelException &&
          error.reason == 'stale_ride_support_case') {
        actionErrorMessage =
            'Bildirim başka bir işlemle güncellendi. Güncel durum yeniden yükleniyor.';
        await refresh();
      } else {
        actionErrorMessage = adminPanelMessage(error);
      }
      await _handleAuthError(error);
      return false;
    } finally {
      isMutating = false;
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
            const {
              'unauthenticated',
              'permission-denied',
            }.contains(error.code))) {
      clearSensitiveState();
      await _handleAuthFailure();
    }
  }

  void clearSensitiveState() {
    items = const [];
    nextCursor = null;
    errorMessage = null;
    actionErrorMessage = null;
    isLoading = false;
    isLoadingMore = false;
    isMutating = false;
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
    actionErrorMessage = null;
    super.dispose();
  }
}
