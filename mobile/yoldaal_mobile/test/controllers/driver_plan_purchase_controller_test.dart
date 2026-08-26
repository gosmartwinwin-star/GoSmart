import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/driver_access/driver_plan_catalog_gateway.dart';
import 'package:yoldaal_mobile/application/driver_access/driver_plan_payment_page_launcher.dart';
import 'package:yoldaal_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:yoldaal_mobile/controllers/driver_plan_purchase_controller.dart';
import 'package:yoldaal_mobile/domain/subscription/driver_pass_plan.dart';

void main() {
  test('catalog load exposes canonical server availability', () async {
    final gateway = _Gateway();
    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();

    expect(controller.catalogLoading, isFalse);
    expect(controller.catalogErrorMessage, isNull);
    expect(
      controller.catalog!.plans.map((entry) => entry.plan).toList(),
      DriverPassPlan.values,
    );
    expect(controller.isPlanEnabled(DriverPassPlan.daily), isTrue);
    expect(controller.isPlanEnabled(DriverPassPlan.weekly), isFalse);
  });

  test('concurrent catalog loads are suppressed', () async {
    final gateway = _Gateway();
    final completer = Completer<DriverPlanCatalogSnapshot>();
    gateway.catalogCompleter = completer;

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    final first = controller.loadCatalog();
    final second = controller.loadCatalog();

    expect(gateway.catalogCalls, 1);

    completer.complete(catalog());
    await Future.wait([first, second]);

    expect(controller.catalog, isNotNull);
  });

  test('catalog failure is safe and retryable', () async {
    final gateway = _Gateway()..catalogFailures = 1;

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.loadCatalog();

    expect(controller.catalog, isNull);
    expect(
      controller.catalogErrorMessage,
      'Plan seçenekleri yüklenemedi. Lütfen tekrar deneyin.',
    );

    await controller.loadCatalog();

    expect(gateway.catalogCalls, 2);
    expect(controller.catalog, isNotNull);
    expect(controller.catalogErrorMessage, isNull);
  });

  test('disabled plan cannot be selected while enabled plan can', () async {
    final gateway = _Gateway();

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.loadCatalog();

    controller.selectPlan(DriverPassPlan.weekly);
    expect(controller.selectedPlan, isNull);

    controller.selectPlan(DriverPassPlan.daily);
    expect(controller.selectedPlan, DriverPassPlan.daily);
  });

  test('catalog reload clears selection when plan becomes disabled', () async {
    final gateway = _Gateway();

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);

    gateway.catalogValue = catalog(version: 'catalog_v2', dailyEnabled: false);

    await controller.loadCatalog();

    expect(controller.selectedPlan, isNull);
    expect(controller.requestId, isNull);
    expect(controller.catalog!.catalogVersion, 'catalog_v2');
  });

  test('plan selection resets prepared state and request identity', () async {
    final gateway = _Gateway();

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();

    expect(controller.prepared, isNotNull);
    expect(controller.requestId, 'request-1');

    controller.selectPlan(DriverPassPlan.monthly);

    expect(controller.selectedPlan, DriverPassPlan.monthly);
    expect(controller.prepared, isNull);
    expect(controller.requestId, isNull);
  });

  test('failed retry reuses the same idempotency requestId', () async {
    final gateway = _Gateway()..prepareFailures = 1;
    var generated = 0;

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-${++generated}',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);

    await controller.prepare();
    await controller.prepare();

    expect(gateway.prepareRequestIds, ['request-1', 'request-1']);
    expect(controller.prepared, isNotNull);
  });

  test('selection cannot change while prepare is in flight', () async {
    final gateway = _Gateway();
    final completer = Completer<PreparedDriverPlanPurchase>();
    gateway.prepareCompleter = completer;

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);

    final future = controller.prepare();

    controller.selectPlan(DriverPassPlan.monthly);

    expect(controller.selectedPlan, DriverPassPlan.daily);
    expect(gateway.prepareCalls, 1);

    completer.complete(prepared(DriverPassPlan.daily));
    await future;
  });

  test('controlled auth errors become safe user messages', () async {
    final gateway = _Gateway()
      ..catalogError = const DriverPlanCatalogException(
        code: 'unauthenticated',
        reason: 'raw_secret_reason',
      );

    final controller = DriverPlanPurchaseController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.loadCatalog();

    expect(
      controller.catalogErrorMessage,
      'Oturumunuzu kontrol edip tekrar deneyin.',
    );
    expect(
      controller.catalogErrorMessage,
      isNot(contains('raw_secret_reason')),
    );
  });

  test(
    'unknown purchase gateway errors receive generic safe message',
    () async {
      final gateway = _Gateway()..unexpectedPrepareFailure = true;

      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-1',
      );
      addTearDown(controller.dispose);

      await controller.loadCatalog();
      controller.selectPlan(DriverPassPlan.daily);
      await controller.prepare();

      expect(
        controller.errorMessage,
        'Plan talebi hazırlanamadı. Lütfen tekrar deneyin.',
      );
      expect(controller.errorMessage, isNot(contains('socket secret')));
    },
  );

  test(
    'checkout initialization uses prepared operation and transient input',
    () async {
      final gateway = _Gateway();
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-1',
      );
      addTearDown(controller.dispose);

      await controller.loadCatalog();
      controller.selectPlan(DriverPassPlan.daily);
      await controller.prepare();

      final buyer = checkoutBuyer();
      final billingAddress = checkoutBillingAddress();

      await controller.initializeCheckout(
        buyer: buyer,
        billingAddress: billingAddress,
      );

      expect(gateway.checkoutCalls, 1);
      expect(
        gateway.checkoutOperationIds,
        [controller.prepared!.purchaseOperationId],
      );
      expect(gateway.checkoutBuyers.single, same(buyer));
      expect(gateway.checkoutBillingAddresses.single, same(billingAddress));
      expect(controller.checkoutInitializing, isFalse);
      expect(controller.checkoutErrorMessage, isNull);
      expect(controller.paymentPageReady, isTrue);
      expect(
        controller.initializedCheckout!.paymentPageUrl,
        Uri.parse('https://sandbox.example.test/payment'),
      );
    },
  );

  test('concurrent checkout initialization is suppressed', () async {
    final gateway = _Gateway();
    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();

    final completer = Completer<InitializedDriverPlanCheckout>();
    gateway.checkoutCompleter = completer;

    final buyer = checkoutBuyer();
    final billingAddress = checkoutBillingAddress();

    final first = controller.initializeCheckout(
      buyer: buyer,
      billingAddress: billingAddress,
    );
    final second = controller.initializeCheckout(
      buyer: buyer,
      billingAddress: billingAddress,
    );

    expect(gateway.checkoutCalls, 1);
    expect(controller.checkoutInitializing, isTrue);

    completer.complete(
      initializedCheckout(controller.prepared!.purchaseOperationId),
    );

    await Future.wait([first, second]);

    expect(gateway.checkoutCalls, 1);
    expect(controller.checkoutInitializing, isFalse);
    expect(controller.paymentPageReady, isTrue);
  });

  test('checkout transport failure is sanitized and retryable', () async {
    final gateway = _Gateway()..unexpectedCheckoutFailure = true;
    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();

    final operationId = controller.prepared!.purchaseOperationId;
    final buyer = checkoutBuyer();
    final billingAddress = checkoutBillingAddress();

    await controller.initializeCheckout(
      buyer: buyer,
      billingAddress: billingAddress,
    );

    expect(controller.paymentPageReady, isFalse);
    expect(controller.checkoutErrorMessage, isNotNull);
    expect(controller.checkoutErrorMessage, isNot(contains('checkout secret')));

    gateway.unexpectedCheckoutFailure = false;

    await controller.initializeCheckout(
      buyer: buyer,
      billingAddress: billingAddress,
    );

    expect(gateway.checkoutCalls, 2);
    expect(gateway.checkoutOperationIds, [operationId, operationId]);
    expect(controller.checkoutErrorMessage, isNull);
    expect(controller.paymentPageReady, isTrue);
  });

  test('payment page launch passes only initialized checkout URL', () async {
    final gateway = _Gateway();
    final launcher = _PaymentPageLauncher();

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      paymentPageLauncher: launcher,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();
    await controller.initializeCheckout(
      buyer: checkoutBuyer(),
      billingAddress: checkoutBillingAddress(),
    );

    final expectedUrl = controller.initializedCheckout!.paymentPageUrl;

    await controller.launchPaymentPage();

    expect(launcher.calls, 1);
    expect(launcher.urls, [expectedUrl]);
    expect(controller.paymentPageLaunching, isFalse);
    expect(controller.paymentPageLaunchErrorMessage, isNull);
    expect(controller.paymentPageReady, isTrue);
    expect(controller.initializedCheckout!.paymentPageUrl, expectedUrl);
  });

  test('concurrent payment page launches are suppressed', () async {
    final gateway = _Gateway();
    final launcher = _PaymentPageLauncher();
    final completer = Completer<void>();
    launcher.completer = completer;

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      paymentPageLauncher: launcher,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();
    await controller.initializeCheckout(
      buyer: checkoutBuyer(),
      billingAddress: checkoutBillingAddress(),
    );

    final first = controller.launchPaymentPage();
    final second = controller.launchPaymentPage();

    expect(launcher.calls, 1);
    expect(controller.paymentPageLaunching, isTrue);

    completer.complete();
    await Future.wait([first, second]);

    expect(launcher.calls, 1);
    expect(controller.paymentPageLaunching, isFalse);
    expect(controller.paymentPageLaunchErrorMessage, isNull);
    expect(controller.paymentPageReady, isTrue);
  });

  test('controlled launcher failure is sanitized and retryable', () async {
    final gateway = _Gateway();
    final launcher = _PaymentPageLauncher()
      ..failure = const DriverPlanPaymentPageLaunchException(
        code: 'unavailable',
      );

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      paymentPageLauncher: launcher,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();
    await controller.initializeCheckout(
      buyer: checkoutBuyer(),
      billingAddress: checkoutBillingAddress(),
    );

    await controller.launchPaymentPage();

    expect(launcher.calls, 1);
    expect(controller.paymentPageReady, isTrue);
    expect(
      controller.paymentPageLaunchErrorMessage,
      'Ödeme sayfası açılamadı. Lütfen tekrar deneyin.',
    );

    launcher.failure = null;

    await controller.launchPaymentPage();

    expect(launcher.calls, 2);
    expect(controller.paymentPageLaunchErrorMessage, isNull);
    expect(controller.paymentPageReady, isTrue);
  });

  test('unexpected launcher failure never leaks raw platform details', () async {
    final gateway = _Gateway();
    final launcher = _PaymentPageLauncher()..unexpectedFailure = true;

    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      paymentPageLauncher: launcher,
      requestIdFactory: () => 'request-1',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();
    await controller.initializeCheckout(
      buyer: checkoutBuyer(),
      billingAddress: checkoutBillingAddress(),
    );

    await controller.launchPaymentPage();

    expect(launcher.calls, 1);
    expect(controller.paymentPageLaunching, isFalse);
    expect(controller.paymentPageReady, isTrue);
    expect(
      controller.paymentPageLaunchErrorMessage,
      'Ödeme sayfası açılamadı. Lütfen tekrar deneyin.',
    );
    expect(
      controller.paymentPageLaunchErrorMessage,
      isNot(contains('raw browser platform secret')),
    );
  });
  test(
    'dispose during async catalog completion does not notify after dispose',
    () async {
      final gateway = _Gateway();
      final completer = Completer<DriverPlanCatalogSnapshot>();
      gateway.catalogCompleter = completer;

      final controller = DriverPlanPurchaseController(gateway: gateway);

      final future = controller.loadCatalog();
      controller.dispose();

      completer.complete(catalog());

      await future;
    },
  );
  test('status gateway falls back from primary gateway', () async {
    final gateway = _Gateway();
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(gateway.statusCalls, 1);
    expect(controller.paymentStatus?.outcome, DriverPlanPaymentOutcome.pending);
    expect(controller.paymentStatusErrorMessage, isNull);
  });

  test('payment status refresh requires initialized checkout', () async {
    final gateway = _Gateway();
    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-status-missing-checkout',
    );
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(gateway.statusCalls, 0);
    expect(controller.paymentStatus, isNull);
    expect(controller.paymentStatusErrorMessage, isNotNull);
  });

  test('payment status refresh sends initialized checkout operation id', () async {
    final gateway = _Gateway();
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(
      gateway.statusOperationIds,
      [controller.initializedCheckout!.purchaseOperationId],
    );
  });

  test('concurrent payment status refresh calls are suppressed', () async {
    final gateway = _Gateway();
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    final completer = Completer<DriverPlanPaymentStatus>();
    gateway.statusCompleter = completer;

    final first = controller.refreshPaymentStatus();
    final second = controller.refreshPaymentStatus();

    expect(gateway.statusCalls, 1);
    expect(controller.paymentStatusRefreshing, isTrue);

    completer.complete(
      DriverPlanPaymentStatus(
        purchaseOperationId:
            controller.initializedCheckout!.purchaseOperationId,
        outcome: DriverPlanPaymentOutcome.pending,
      ),
    );

    await Future.wait([first, second]);

    expect(gateway.statusCalls, 1);
    expect(controller.paymentStatusRefreshing, isFalse);
    expect(controller.paymentStatus?.outcome, DriverPlanPaymentOutcome.pending);
  });

  test('pending payment outcome is stored', () async {
    final gateway = _Gateway()
      ..statusOutcome = DriverPlanPaymentOutcome.pending;
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(controller.paymentStatus?.outcome, DriverPlanPaymentOutcome.pending);
  });

  test('paymentReview payment outcome is stored', () async {
    final gateway = _Gateway()
      ..statusOutcome = DriverPlanPaymentOutcome.paymentReview;
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(
      controller.paymentStatus?.outcome,
      DriverPlanPaymentOutcome.paymentReview,
    );
  });

  test('paymentFailed payment outcome is stored', () async {
    final gateway = _Gateway()
      ..statusOutcome = DriverPlanPaymentOutcome.paymentFailed;
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(
      controller.paymentStatus?.outcome,
      DriverPlanPaymentOutcome.paymentFailed,
    );
  });

  test('settled payment outcome is stored', () async {
    final gateway = _Gateway()
      ..statusOutcome = DriverPlanPaymentOutcome.settled;
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(controller.paymentStatus?.outcome, DriverPlanPaymentOutcome.settled);
  });

  test('controlled payment status read error is surfaced safely', () async {
    final gateway = _Gateway()
      ..statusError = const DriverPlanPurchaseException(
        code: 'permission-denied',
        reason: 'raw_backend_reason',
      );
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(controller.paymentStatus, isNull);
    expect(
      controller.paymentStatusErrorMessage,
      'Bu \u00f6deme durumu i\u00e7in yetkiniz bulunmuyor.',
    );
    expect(
      controller.paymentStatusErrorMessage,
      isNot(contains('raw_backend_reason')),
    );
  });

  test('unexpected payment status error is sanitized', () async {
    final gateway = _Gateway()..unexpectedStatusFailure = true;
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(controller.paymentStatus, isNull);
    expect(
      controller.paymentStatusErrorMessage,
      '\u00d6deme durumu kontrol edilemedi. L\u00fctfen tekrar deneyin.',
    );
    expect(
      controller.paymentStatusErrorMessage,
      isNot(contains('raw payment status secret')),
    );
  });

  test('status read error preserves previous authoritative status', () async {
    final gateway = _Gateway()
      ..statusOutcome = DriverPlanPaymentOutcome.pending;
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(controller.paymentStatus?.outcome, DriverPlanPaymentOutcome.pending);

    gateway.statusError =
        const DriverPlanPurchaseException(code: 'unavailable');

    await controller.refreshPaymentStatus();

    expect(controller.paymentStatus?.outcome, DriverPlanPaymentOutcome.pending);
    expect(controller.paymentStatusErrorMessage, isNotNull);
  });

  test('plan change clears authoritative payment status', () async {
    final gateway = _Gateway();
    final controller = await _readyForPaymentStatus(gateway);
    addTearDown(controller.dispose);

    await controller.refreshPaymentStatus();

    expect(controller.paymentStatus, isNotNull);

    controller.selectPlan(DriverPassPlan.monthly);

    expect(controller.paymentStatus, isNull);
    expect(controller.paymentStatusErrorMessage, isNull);
  });

  test('successful new prepare keeps stale payment status state cleared', () async {
    final gateway = _Gateway();
    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-new-prepare',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);

    await controller.refreshPaymentStatus();
    expect(controller.paymentStatusErrorMessage, isNotNull);

    await controller.prepare();

    expect(controller.prepared, isNotNull);
    expect(controller.paymentStatus, isNull);
    expect(controller.paymentStatusErrorMessage, isNull);
  });

  test('successful new checkout clears pre-checkout status read error', () async {
    final gateway = _Gateway();
    final controller = DriverPlanPurchaseController(
      gateway: gateway,
      requestIdFactory: () => 'request-new-checkout',
    );
    addTearDown(controller.dispose);

    await controller.loadCatalog();
    controller.selectPlan(DriverPassPlan.daily);
    await controller.prepare();

    await controller.refreshPaymentStatus();
    expect(controller.paymentStatusErrorMessage, isNotNull);

    await controller.initializeCheckout(
      buyer: checkoutBuyer(),
      billingAddress: checkoutBillingAddress(),
    );

    expect(controller.paymentPageReady, isTrue);
    expect(controller.paymentStatus, isNull);
    expect(controller.paymentStatusErrorMessage, isNull);
  });

  test('payment page launch success does not fabricate payment status', () async {
    final gateway = _Gateway();
    final launcher = _PaymentPageLauncher();
    final controller = await _readyForPaymentStatus(
      gateway,
      paymentPageLauncher: launcher,
    );
    addTearDown(controller.dispose);

    expect(controller.paymentStatus, isNull);

    await controller.launchPaymentPage();

    expect(launcher.calls, 1);
    expect(gateway.statusCalls, 0);
    expect(controller.paymentStatus, isNull);
    expect(controller.paymentStatusErrorMessage, isNull);
  });
}

Future<DriverPlanPurchaseController> _readyForPaymentStatus(
  _Gateway gateway, {
  DriverPlanPaymentPageLauncher? paymentPageLauncher,
}) async {
  final controller = DriverPlanPurchaseController(
    gateway: gateway,
    paymentPageLauncher: paymentPageLauncher,
    requestIdFactory: () => 'request-status-ready',
  );

  await controller.loadCatalog();
  controller.selectPlan(DriverPassPlan.daily);
  await controller.prepare();
  await controller.initializeCheckout(
    buyer: checkoutBuyer(),
    billingAddress: checkoutBillingAddress(),
  );

  return controller;
}

DriverPlanCatalogSnapshot catalog({
  String version = 'catalog_v1',
  bool dailyEnabled = true,
}) {
  return DriverPlanCatalogSnapshot(
    catalogVersion: version,
    plans: [
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.daily,
        enabled: dailyEnabled,
        amountMinor: 0,
        currency: 'TRY',
      ),
      const DriverPlanCatalogEntry(
        plan: DriverPassPlan.weekly,
        enabled: false,
        amountMinor: 200,
        currency: 'TRY',
      ),
      const DriverPlanCatalogEntry(
        plan: DriverPassPlan.monthly,
        enabled: true,
        amountMinor: 300,
        currency: 'TRY',
      ),
      const DriverPlanCatalogEntry(
        plan: DriverPassPlan.quarterly,
        enabled: true,
        amountMinor: 400,
        currency: 'TRY',
      ),
    ],
  );
}

PreparedDriverPlanPurchase prepared(DriverPassPlan plan) {
  return PreparedDriverPlanPurchase(
    purchaseOperationId: List<String>.filled(64, 'a').join(),
    status: 'pending',
    catalogVersion: 'catalog_v1',
    plan: plan,
    amountMinor: 1234,
    currency: 'EUR',
  );
}

DriverPlanCheckoutBuyer checkoutBuyer() {
  return const DriverPlanCheckoutBuyer(
    name: 'Test',
    surname: 'Buyer',
    identityNumber: '11111111111',
    email: 'buyer@example.test',
    registrationAddress: 'Test Registration Address',
    city: 'Istanbul',
    country: 'Turkey',
    zipCode: '34000',
  );
}

DriverPlanCheckoutBillingAddress checkoutBillingAddress() {
  return const DriverPlanCheckoutBillingAddress(
    address: 'Test Billing Address',
    contactName: 'Test Buyer',
    city: 'Istanbul',
    country: 'Turkey',
    zipCode: '34000',
  );
}

InitializedDriverPlanCheckout initializedCheckout(String purchaseOperationId) {
  return InitializedDriverPlanCheckout(
    provider: 'iyzico_checkout_form',
    purchaseOperationId: purchaseOperationId,
    conversationId: 'conversation-1',
    token: 'token-1',
    paymentPageUrl: Uri.parse('https://sandbox.example.test/payment'),
  );
}

class _PaymentPageLauncher implements DriverPlanPaymentPageLauncher {
  int calls = 0;
  final List<Uri> urls = [];
  Completer<void>? completer;
  DriverPlanPaymentPageLaunchException? failure;
  bool unexpectedFailure = false;

  @override
  Future<void> launchPaymentPage(Uri paymentPageUrl) async {
    calls++;
    urls.add(paymentPageUrl);

    if (failure case final error?) {
      throw error;
    }

    if (unexpectedFailure) {
      throw StateError('raw browser platform secret');
    }

    if (completer case final pending?) {
      await pending.future;
    }
  }
}
class _Gateway
    implements
        DriverPlanPurchaseGateway,
        DriverPlanCatalogGateway,
        DriverPlanCheckoutGateway,
        DriverPlanPaymentStatusGateway {
  DriverPlanCatalogSnapshot catalogValue = catalog();
  int catalogFailures = 0;
  DriverPlanCatalogException? catalogError;
  Completer<DriverPlanCatalogSnapshot>? catalogCompleter;
  int catalogCalls = 0;

  int prepareFailures = 0;
  bool unexpectedPrepareFailure = false;
  Completer<PreparedDriverPlanPurchase>? prepareCompleter;
  int prepareCalls = 0;
  final List<String> prepareRequestIds = [];

  bool unexpectedCheckoutFailure = false;
  Completer<InitializedDriverPlanCheckout>? checkoutCompleter;
  int checkoutCalls = 0;
  final List<String> checkoutOperationIds = [];
  final List<DriverPlanCheckoutBuyer> checkoutBuyers = [];
  final List<DriverPlanCheckoutBillingAddress> checkoutBillingAddresses = [];

  int statusCalls = 0;
  final List<String> statusOperationIds = [];
  DriverPlanPaymentOutcome statusOutcome =
      DriverPlanPaymentOutcome.pending;
  DriverPlanPurchaseException? statusError;
  bool unexpectedStatusFailure = false;
  Completer<DriverPlanPaymentStatus>? statusCompleter;

  @override
  Future<DriverPlanCatalogSnapshot> load() async {
    catalogCalls++;

    if (catalogError case final error?) {
      throw error;
    }

    if (catalogFailures > 0) {
      catalogFailures--;
      throw const DriverPlanCatalogException(code: 'unavailable');
    }

    if (catalogCompleter case final completer?) {
      return completer.future;
    }

    return catalogValue;
  }

  @override
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  }) async {
    prepareCalls++;
    prepareRequestIds.add(requestId);

    if (unexpectedPrepareFailure) {
      throw StateError('socket secret');
    }

    if (prepareFailures > 0) {
      prepareFailures--;
      throw const DriverPlanPurchaseException(code: 'unavailable');
    }

    if (prepareCompleter case final completer?) {
      return completer.future;
    }

    return prepared(plan);
  }

  @override
  Future<InitializedDriverPlanCheckout> initializeCheckout({
    required String purchaseOperationId,
    required DriverPlanCheckoutBuyer buyer,
    required DriverPlanCheckoutBillingAddress billingAddress,
  }) async {
    checkoutCalls++;
    checkoutOperationIds.add(purchaseOperationId);
    checkoutBuyers.add(buyer);
    checkoutBillingAddresses.add(billingAddress);

    if (unexpectedCheckoutFailure) {
      throw StateError('checkout secret');
    }

    if (checkoutCompleter case final completer?) {
      return completer.future;
    }

    return initializedCheckout(purchaseOperationId);
  }

  @override
  Future<DriverPlanPaymentStatus> getPaymentStatus({
    required String purchaseOperationId,
  }) async {
    statusCalls++;
    statusOperationIds.add(purchaseOperationId);

    if (statusError case final error?) {
      throw error;
    }

    if (unexpectedStatusFailure) {
      throw StateError('raw payment status secret');
    }

    if (statusCompleter case final completer?) {
      return completer.future;
    }

    return DriverPlanPaymentStatus(
      purchaseOperationId: purchaseOperationId,
      outcome: statusOutcome,
    );
  }
}
