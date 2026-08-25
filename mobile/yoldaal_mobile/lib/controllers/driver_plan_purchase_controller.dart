import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../application/driver_access/driver_plan_catalog_gateway.dart';
import '../application/driver_access/driver_plan_payment_page_launcher.dart';
import '../application/driver_access/driver_plan_purchase_gateway.dart';
import '../domain/subscription/driver_pass_plan.dart';

class DriverPlanPurchaseController extends ChangeNotifier {
  DriverPlanPurchaseController({
    required DriverPlanPurchaseGateway gateway,
    DriverPlanCatalogGateway? catalogGateway,
    DriverPlanCheckoutGateway? checkoutGateway,
    DriverPlanPaymentPageLauncher? paymentPageLauncher,
    String Function()? requestIdFactory,
  }) : _gateway = gateway,
       _catalogGateway =
           catalogGateway ??
           (gateway is DriverPlanCatalogGateway
               ? gateway as DriverPlanCatalogGateway
               : null),
       _checkoutGateway =
           checkoutGateway ??
           (gateway is DriverPlanCheckoutGateway
               ? gateway as DriverPlanCheckoutGateway
               : null),
       _paymentPageLauncher = paymentPageLauncher,
       _requestIdFactory = requestIdFactory ?? _secureRequestId;

  final DriverPlanPurchaseGateway _gateway;
  final DriverPlanCatalogGateway? _catalogGateway;
  final DriverPlanCheckoutGateway? _checkoutGateway;
  final DriverPlanPaymentPageLauncher? _paymentPageLauncher;
  final String Function() _requestIdFactory;

  DriverPlanCatalogSnapshot? _catalog;
  bool _catalogLoading = false;
  String? _catalogErrorMessage;

  DriverPassPlan? _selectedPlan;
  bool _preparing = false;
  PreparedDriverPlanPurchase? _prepared;
  String? _errorMessage;
  String? _requestId;

  bool _checkoutInitializing = false;
  InitializedDriverPlanCheckout? _initializedCheckout;
  String? _checkoutErrorMessage;

  bool _paymentPageLaunching = false;
  String? _paymentPageLaunchErrorMessage;

  bool _disposed = false;

  DriverPlanCatalogSnapshot? get catalog => _catalog;
  bool get catalogLoading => _catalogLoading;
  String? get catalogErrorMessage => _catalogErrorMessage;

  DriverPassPlan? get selectedPlan => _selectedPlan;
  bool get preparing => _preparing;
  PreparedDriverPlanPurchase? get prepared => _prepared;
  String? get errorMessage => _errorMessage;
  String? get requestId => _requestId;

  bool get checkoutAvailable => _checkoutGateway != null;
  bool get checkoutInitializing => _checkoutInitializing;
  InitializedDriverPlanCheckout? get initializedCheckout => _initializedCheckout;
  String? get checkoutErrorMessage => _checkoutErrorMessage;
  bool get paymentPageReady => _initializedCheckout != null;
  bool get paymentPageLaunchAvailable => _paymentPageLauncher != null;
  bool get paymentPageLaunching => _paymentPageLaunching;
  String? get paymentPageLaunchErrorMessage =>
      _paymentPageLaunchErrorMessage;

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
    if (_disposed ||
        _catalogLoading ||
        _preparing ||
        _checkoutInitializing ||
        _paymentPageLaunching ||
        !isPlanEnabled(plan)) {
      return;
    }

    if (_selectedPlan == plan) {
      return;
    }

    _selectedPlan = plan;
    _prepared = null;
    _errorMessage = null;
    _requestId = null;
    _initializedCheckout = null;
    _checkoutErrorMessage = null;
    _paymentPageLaunchErrorMessage = null;
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
      _initializedCheckout = null;
      _checkoutErrorMessage = null;
      _paymentPageLaunchErrorMessage = null;
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

  Future<void> initializeCheckout({
    required DriverPlanCheckoutBuyer buyer,
    required DriverPlanCheckoutBillingAddress billingAddress,
  }) async {
    if (_disposed || _checkoutInitializing || _initializedCheckout != null) {
      return;
    }

    final prepared = _prepared;

    if (prepared == null) {
      _checkoutErrorMessage =
          '\u00d6deme ad\u0131m\u0131 hen\u00fcz haz\u0131r de\u011fil. '
          'L\u00fctfen \u00f6nce plan talebini haz\u0131rlay\u0131n.';
      _notify();
      return;
    }

    final gateway = _checkoutGateway;

    if (gateway == null) {
      _checkoutErrorMessage =
          '\u00d6deme sayfas\u0131 haz\u0131rlanamad\u0131. '
          'L\u00fctfen tekrar deneyin.';
      _notify();
      return;
    }

    _checkoutInitializing = true;
    _checkoutErrorMessage = null;
    _notify();

    try {
      final result = await gateway.initializeCheckout(
        purchaseOperationId: prepared.purchaseOperationId,
        buyer: buyer,
        billingAddress: billingAddress,
      );

      if (_disposed) {
        return;
      }

      if (_prepared?.purchaseOperationId != prepared.purchaseOperationId ||
          result.purchaseOperationId != prepared.purchaseOperationId) {
        _checkoutErrorMessage =
            '\u00d6deme sayfas\u0131 haz\u0131rlanamad\u0131. '
            'L\u00fctfen tekrar deneyin.';
        return;
      }

      _initializedCheckout = result;
      _checkoutErrorMessage = null;
      _paymentPageLaunchErrorMessage = null;
    } on DriverPlanPurchaseException catch (error) {
      if (_disposed) {
        return;
      }

      _checkoutErrorMessage = _safeCheckoutMessage(error);
    } catch (_) {
      if (_disposed) {
        return;
      }

      _checkoutErrorMessage =
          '\u00d6deme sayfas\u0131 haz\u0131rlanamad\u0131. '
          'L\u00fctfen tekrar deneyin.';
    } finally {
      _checkoutInitializing = false;
      _notify();
    }
  }

  Future<void> launchPaymentPage() async {
    if (_disposed || _paymentPageLaunching) {
      return;
    }

    final checkout = _initializedCheckout;

    if (checkout == null) {
      _paymentPageLaunchErrorMessage =
          'Ödeme sayfası henüz hazır değil. Lütfen tekrar deneyin.';
      _notify();
      return;
    }

    final launcher = _paymentPageLauncher;

    if (launcher == null) {
      _paymentPageLaunchErrorMessage =
          'Ödeme sayfası açılamadı. Lütfen tekrar deneyin.';
      _notify();
      return;
    }

    _paymentPageLaunching = true;
    _paymentPageLaunchErrorMessage = null;
    _notify();

    try {
      await launcher.launchPaymentPage(checkout.paymentPageUrl);

      if (_disposed) {
        return;
      }

      _paymentPageLaunchErrorMessage = null;
    } on DriverPlanPaymentPageLaunchException {
      if (_disposed) {
        return;
      }

      _paymentPageLaunchErrorMessage =
          'Ödeme sayfası açılamadı. Lütfen tekrar deneyin.';
    } catch (_) {
      if (_disposed) {
        return;
      }

      _paymentPageLaunchErrorMessage =
          'Ödeme sayfası açılamadı. Lütfen tekrar deneyin.';
    } finally {
      _paymentPageLaunching = false;
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

  String _safeCheckoutMessage(DriverPlanPurchaseException error) {
    return switch (error.code) {
      'unauthenticated' =>
        'Oturumunuzu kontrol edip tekrar deneyin.',
      'permission-denied' =>
        'Bu \u00f6deme talebi i\u00e7in yetkiniz bulunmuyor.',
      _ =>
        '\u00d6deme sayfas\u0131 haz\u0131rlanamad\u0131. '
            'L\u00fctfen tekrar deneyin.',
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
