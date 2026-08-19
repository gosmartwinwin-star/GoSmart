import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../application/driver_access/driver_plan_catalog_gateway.dart';
import '../application/driver_access/driver_plan_purchase_gateway.dart';
import '../domain/subscription/driver_pass_plan.dart';

class DriverPlanPurchaseController extends ChangeNotifier {
  DriverPlanPurchaseController({
    required DriverPlanPurchaseGateway gateway,
    DriverPlanCatalogGateway? catalogGateway,
    String Function()? requestIdFactory,
  }) : _gateway = gateway,
       _catalogGateway =
           catalogGateway ??
           (gateway is DriverPlanCatalogGateway
               ? gateway as DriverPlanCatalogGateway
               : null),
       _requestIdFactory = requestIdFactory ?? _secureRequestId;

  final DriverPlanPurchaseGateway _gateway;
  final DriverPlanCatalogGateway? _catalogGateway;
  final String Function() _requestIdFactory;

  DriverPlanCatalogSnapshot? _catalog;
  bool _catalogLoading = false;
  String? _catalogErrorMessage;

  DriverPassPlan? _selectedPlan;
  bool _preparing = false;
  PreparedDriverPlanPurchase? _prepared;
  String? _errorMessage;
  String? _requestId;
  bool _disposed = false;

  DriverPlanCatalogSnapshot? get catalog => _catalog;
  bool get catalogLoading => _catalogLoading;
  String? get catalogErrorMessage => _catalogErrorMessage;

  DriverPassPlan? get selectedPlan => _selectedPlan;
  bool get preparing => _preparing;
  PreparedDriverPlanPurchase? get prepared => _prepared;
  String? get errorMessage => _errorMessage;
  String? get requestId => _requestId;

  bool isPlanEnabled(DriverPassPlan plan) {
    final current = _catalog;

    if (current == null) {
      return false;
    }

    return current.entryFor(plan)?.enabled == true;
  }

  Future<void> loadCatalog() async {
    if (_disposed || _catalogLoading || _preparing || _prepared != null) {
      return;
    }

    final gateway = _catalogGateway;

    if (gateway == null) {
      _catalog = null;
      _selectedPlan = null;
      _requestId = null;
      _catalogErrorMessage =
          'Plan seçenekleri yüklenemedi. Lütfen tekrar deneyin.';
      _notify();
      return;
    }

    _catalogLoading = true;
    _catalogErrorMessage = null;
    _notify();

    final previousVersion = _catalog?.catalogVersion;

    try {
      final value = await gateway.load();

      if (_disposed) {
        return;
      }

      _catalog = value;

      if (previousVersion != null && previousVersion != value.catalogVersion) {
        _requestId = null;
      }

      final selected = _selectedPlan;

      if (selected != null && !isPlanEnabled(selected)) {
        _selectedPlan = null;
        _requestId = null;
        _errorMessage = null;
      }
    } on DriverPlanCatalogException catch (error) {
      if (_disposed) {
        return;
      }

      _catalog = null;
      _selectedPlan = null;
      _requestId = null;
      _catalogErrorMessage = _safeCatalogMessage(error);
    } catch (_) {
      if (_disposed) {
        return;
      }

      _catalog = null;
      _selectedPlan = null;
      _requestId = null;
      _catalogErrorMessage =
          'Plan seçenekleri yüklenemedi. Lütfen tekrar deneyin.';
    } finally {
      _catalogLoading = false;
      _notify();
    }
  }

  void selectPlan(DriverPassPlan plan) {
    if (_disposed || _catalogLoading || _preparing || !isPlanEnabled(plan)) {
      return;
    }

    if (_selectedPlan == plan) {
      return;
    }

    _selectedPlan = plan;
    _prepared = null;
    _errorMessage = null;
    _requestId = null;
    _notify();
  }

  Future<void> prepare() async {
    if (_disposed || _preparing || _prepared != null) {
      return;
    }

    if (_catalog == null) {
      _errorMessage =
          'Plan seçenekleri henüz hazır değil. Lütfen tekrar deneyin.';
      _notify();
      return;
    }

    final plan = _selectedPlan;

    if (plan == null) {
      _errorMessage = 'Lütfen bir plan seçin.';
      _notify();
      return;
    }

    if (!isPlanEnabled(plan)) {
      _selectedPlan = null;
      _requestId = null;
      _errorMessage = 'Seçtiğiniz plan şu anda kullanılamıyor.';
      _notify();
      return;
    }

    _preparing = true;
    _errorMessage = null;
    _requestId ??= _requestIdFactory();
    final operationRequestId = _requestId!;
    _notify();

    try {
      final result = await _gateway.prepare(
        plan: plan,
        requestId: operationRequestId,
      );

      if (_disposed) {
        return;
      }

      _prepared = result;
      _errorMessage = null;
    } on DriverPlanPurchaseException catch (error) {
      if (_disposed) {
        return;
      }

      _errorMessage = _safePurchaseMessage(error);
    } catch (_) {
      if (_disposed) {
        return;
      }

      _errorMessage = 'Plan talebi hazırlanamadı. Lütfen tekrar deneyin.';
    } finally {
      _preparing = false;
      _notify();
    }
  }

  String _safeCatalogMessage(DriverPlanCatalogException error) {
    return switch (error.code) {
      'unauthenticated' => 'Oturumunuzu kontrol edip tekrar deneyin.',
      'permission-denied' =>
        'Plan seçeneklerini görüntülemek için yetkiniz bulunmuyor.',
      _ => 'Plan seçenekleri yüklenemedi. Lütfen tekrar deneyin.',
    };
  }

  String _safePurchaseMessage(DriverPlanPurchaseException error) {
    return switch (error.code) {
      'unauthenticated' => 'Oturumunuzu kontrol edip tekrar deneyin.',
      'permission-denied' => 'Bu plan talebi için yetkiniz bulunmuyor.',
      _ => 'Plan talebi hazırlanamadı. Lütfen tekrar deneyin.',
    };
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static String _secureRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      24,
      (_) => random.nextInt(256),
      growable: false,
    );

    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
