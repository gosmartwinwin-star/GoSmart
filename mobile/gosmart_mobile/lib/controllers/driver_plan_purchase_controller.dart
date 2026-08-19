import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../application/driver_access/driver_plan_purchase_gateway.dart';
import '../domain/subscription/driver_pass_plan.dart';

typedef DriverPlanPurchaseRequestIdFactory = String Function();

class DriverPlanPurchaseController extends ChangeNotifier {
  DriverPlanPurchaseController({
    required DriverPlanPurchaseGateway gateway,
    DriverPlanPurchaseRequestIdFactory? requestIdFactory,
  }) : _gateway = gateway,
       _requestIdFactory = requestIdFactory ?? _secureRequestId;

  final DriverPlanPurchaseGateway _gateway;
  final DriverPlanPurchaseRequestIdFactory _requestIdFactory;

  DriverPassPlan? _selectedPlan;
  bool _preparing = false;
  PreparedDriverPlanPurchase? _prepared;
  String? _errorMessage;
  String? _requestId;
  bool _disposed = false;

  DriverPassPlan? get selectedPlan => _selectedPlan;
  bool get preparing => _preparing;
  PreparedDriverPlanPurchase? get prepared => _prepared;
  String? get errorMessage => _errorMessage;

  bool get canPrepare =>
      _selectedPlan != null && !_preparing && _prepared == null;

  void selectPlan(DriverPassPlan plan) {
    if (_preparing || _selectedPlan == plan) {
      return;
    }

    _selectedPlan = plan;
    _prepared = null;
    _errorMessage = null;
    _requestId = null;
    _notifySafely();
  }

  Future<void> prepare() async {
    if (_preparing || _prepared != null) {
      return;
    }

    final plan = _selectedPlan;

    if (plan == null) {
      _errorMessage = 'Lütfen bir plan seçin.';
      _notifySafely();
      return;
    }

    final requestId = _requestId ??= _requestIdFactory();

    if (requestId.trim().isEmpty) {
      _errorMessage = 'Plan talebi hazırlanamadı. Lütfen tekrar deneyin.';
      _notifySafely();
      return;
    }

    _preparing = true;
    _errorMessage = null;
    _notifySafely();

    try {
      final result = await _gateway.prepare(plan: plan, requestId: requestId);

      if (_disposed) {
        return;
      }

      _prepared = result;
    } on DriverPlanPurchaseException catch (error) {
      if (_disposed) {
        return;
      }

      _errorMessage = _safeMessage(error);
    } catch (_) {
      if (_disposed) {
        return;
      }

      _errorMessage = 'Plan talebi hazırlanamadı. Lütfen tekrar deneyin.';
    } finally {
      if (!_disposed) {
        _preparing = false;
        _notifySafely();
      }
    }
  }

  String _safeMessage(DriverPlanPurchaseException error) {
    return switch (error.code) {
      'unauthenticated' => 'Oturumunuzu kontrol edip tekrar deneyin.',
      'permission-denied' => 'Bu işlem için sürücü erişiminiz bulunmuyor.',
      _ => 'Plan talebi hazırlanamadı. Lütfen tekrar deneyin.',
    };
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _secureRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));

  return base64Url.encode(bytes).replaceAll('=', '');
}
