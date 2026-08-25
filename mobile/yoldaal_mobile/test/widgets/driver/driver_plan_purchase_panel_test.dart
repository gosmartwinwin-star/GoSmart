import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/driver_access/driver_plan_catalog_gateway.dart';
import 'package:yoldaal_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:yoldaal_mobile/application/driver_access/driver_plan_payment_page_launcher.dart';
import 'package:yoldaal_mobile/controllers/driver_plan_purchase_controller.dart';
import 'package:yoldaal_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:yoldaal_mobile/widgets/driver/driver_plan_purchase_panel.dart';

void main() {
  testWidgets('catalog loads before plan selection is enabled', (tester) async {
    final gateway = _Gateway();
    final completer = Completer<DriverPlanCatalogSnapshot>();
    gateway.catalogCompleter = completer;

    final controller = await _showPanel(tester, gateway);
    addTearDown(controller.dispose);

    expect(
      find.byKey(const ValueKey('driver-plan-catalog-loading')),
      findsOneWidget,
    );
    expect(find.byType(ChoiceChip), findsNothing);

    completer.complete(catalog());
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(4));
  });

  testWidgets(
    'canonical four plans are visible and server-disabled plan is blocked',
    (tester) async {
      final gateway = _Gateway();
      final controller = await _showPanel(tester, gateway);
      addTearDown(controller.dispose);

      await tester.pumpAndSettle();

      expect(find.text('Günlük'), findsOneWidget);
      expect(find.text('Haftalık'), findsOneWidget);
      expect(find.text('Aylık'), findsOneWidget);
      expect(find.text('3 Aylık'), findsOneWidget);

      final weekly = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('driver-plan-weekly')),
      );

      expect(weekly.onSelected, isNull);

      await tester.tap(find.byKey(const ValueKey('driver-plan-daily')));
      await tester.pump();

      expect(controller.selectedPlan, DriverPassPlan.daily);
    },
  );

  testWidgets('catalog error is explicit and retryable', (tester) async {
    final gateway = _Gateway()..catalogFailures = 1;
    final controller = await _showPanel(tester, gateway);
    addTearDown(controller.dispose);

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('driver-plan-catalog-error')),
      findsOneWidget,
    );
    expect(find.text('Planları Tekrar Dene'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('driver-plan-catalog-retry')));
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(4));
    expect(gateway.catalogCalls, 2);
  });

  testWidgets('raw amountMinor and currency are not rendered as price', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = await _showPanel(tester, gateway);
    addTearDown(controller.dispose);

    await tester.pumpAndSettle();

    expect(find.text('1234'), findsNothing);
    expect(find.text('TRY'), findsNothing);
    expect(find.textContaining('12.34'), findsNothing);
  });

  testWidgets('prepare failure remains retryable with existing purchase flow', (
    tester,
  ) async {
    final gateway = _Gateway()..prepareFailures = 1;
    final controller = await _showPanel(tester, gateway);
    addTearDown(controller.dispose);

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('driver-plan-daily')));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('driver-plan-purchase-prepare')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Plan talebi hazırlanamadı. Lütfen tekrar deneyin.'),
      findsOneWidget,
    );
    expect(find.text('Tekrar Dene'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('driver-plan-purchase-prepare')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('driver-plan-purchase-prepared')),
      findsOneWidget,
    );
  });

  testWidgets(
    'prepared state remains pending-only and never claims activation',
    (tester) async {
      final gateway = _Gateway();
      final controller = await _showPanel(tester, gateway);
      addTearDown(controller.dispose);

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('driver-plan-daily')));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('driver-plan-purchase-prepare')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Günlük plan talebi hazırlandı.'), findsOneWidget);
      expect(
        find.text('Ödeme veya paket aktivasyonu henüz tamamlanmadı.'),
        findsOneWidget,
      );
      expect(find.textContaining('aktif edildi'), findsNothing);
    },
  );

  testWidgets(
    'blank transient checkout form does not initialize checkout',
    (tester) async {
      final gateway = _Gateway();
      final controller = await _showPanel(tester, gateway);
      addTearDown(controller.dispose);

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('driver-plan-daily')),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('driver-plan-purchase-prepare')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('driver-plan-checkout-transient-note')),
        findsOneWidget,
      );

      final initialize = find.byKey(
        const ValueKey('driver-plan-checkout-initialize'),
      );

      await tester.ensureVisible(initialize);
      await tester.pumpAndSettle();
      await tester.tap(initialize);
      await tester.pump();

      expect(gateway.checkoutCalls, 0);
      expect(find.text('Bu alan zorunludur.'), findsWidgets);
      expect(controller.paymentPageReady, isFalse);
    },
  );

  testWidgets(
    'transient buyer and billing input initializes payment page without launch',
    (tester) async {
      final gateway = _Gateway();
      final controller = await _showPanel(tester, gateway);
      addTearDown(controller.dispose);

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('driver-plan-daily')),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('driver-plan-purchase-prepare')),
      );
      await tester.pumpAndSettle();

      await _fillCheckoutForm(tester);

      final initialize = find.byKey(
        const ValueKey('driver-plan-checkout-initialize'),
      );

      await tester.ensureVisible(initialize);
      await tester.pumpAndSettle();
      await tester.tap(initialize);
      await tester.pumpAndSettle();

      expect(gateway.checkoutCalls, 1);

      final buyer = gateway.checkoutBuyers.single;
      expect(buyer.name, 'Test');
      expect(buyer.surname, 'Buyer');
      expect(buyer.identityNumber, '11111111111');
      expect(buyer.email, 'buyer@example.test');
      expect(buyer.registrationAddress, 'Registration Address');
      expect(buyer.city, 'Istanbul');
      expect(buyer.country, 'Turkey');
      expect(buyer.zipCode, '34000');

      final billing = gateway.checkoutBillingAddresses.single;
      expect(billing.address, 'Billing Address');
      expect(billing.contactName, 'Test Buyer');
      expect(billing.city, 'Istanbul');
      expect(billing.country, 'Turkey');
      expect(billing.zipCode, '34000');

      expect(
        gateway.checkoutOperationIds.single,
        controller.prepared!.purchaseOperationId,
      );

      expect(
        find.byKey(const ValueKey('driver-plan-checkout-ready')),
        findsOneWidget,
      );

      expect(
        find.textContaining('https://sandbox.example.test/payment'),
        findsNothing,
      );
      expect(find.textContaining('token-1'), findsNothing);
      expect(find.textContaining('conversation-1'), findsNothing);

      expect(
        find.byKey(const ValueKey('driver-plan-buyer-identity-number')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'checkout failure keeps transient form retryable',
    (tester) async {
      final gateway = _Gateway()..checkoutFailures = 1;
      final controller = await _showPanel(tester, gateway);
      addTearDown(controller.dispose);

      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('driver-plan-daily')),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('driver-plan-purchase-prepare')),
      );
      await tester.pumpAndSettle();

      await _fillCheckoutForm(tester);

      final initialize = find.byKey(
        const ValueKey('driver-plan-checkout-initialize'),
      );

      await tester.ensureVisible(initialize);
      await tester.pumpAndSettle();
      await tester.tap(initialize);
      await tester.pumpAndSettle();

      expect(gateway.checkoutCalls, 1);
      expect(controller.paymentPageReady, isFalse);

      expect(
        find.byKey(const ValueKey('driver-plan-checkout-error')),
        findsOneWidget,
      );

      await tester.ensureVisible(initialize);
      await tester.pumpAndSettle();
      await tester.tap(initialize);
      await tester.pumpAndSettle();

      expect(gateway.checkoutCalls, 2);
      expect(controller.checkoutErrorMessage, isNull);
      expect(controller.paymentPageReady, isTrue);

      expect(
        find.byKey(const ValueKey('driver-plan-checkout-ready')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'payment page ready exposes safe external launch UX',
    (tester) async {
      final gateway = _Gateway();
      final launcher = _PaymentPageLauncher();

      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        paymentPageLauncher: launcher,
        requestIdFactory: () => 'request-launch',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriverPlanPurchasePanel(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      controller.selectPlan(DriverPassPlan.daily);
      await controller.prepare();

      await controller.initializeCheckout(
        buyer: const DriverPlanCheckoutBuyer(
          name: 'Test',
          surname: 'Buyer',
          identityNumber: '11111111111',
          email: 'buyer@example.test',
          registrationAddress: 'Test Registration Address',
          city: 'Istanbul',
          country: 'Turkey',
          zipCode: '34000',
        ),
        billingAddress: const DriverPlanCheckoutBillingAddress(
          address: 'Test Billing Address',
          contactName: 'Test Buyer',
          city: 'Istanbul',
          country: 'Turkey',
          zipCode: '34000',
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('driver-plan-checkout-ready'),
        ),
        findsOneWidget,
      );

      final openButton = find.byKey(
        const ValueKey('driver-plan-checkout-open'),
      );

      expect(openButton, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('driver-plan-checkout-browser-note'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(openButton);
      await tester.tap(openButton);
      await tester.pumpAndSettle();

      expect(launcher.calls, 1);
      expect(
        launcher.urls,
        [controller.initializedCheckout!.paymentPageUrl],
      );
      expect(controller.paymentPageReady, isTrue);
      expect(
        controller.paymentPageLaunchErrorMessage,
        isNull,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-checkout-launch-error'),
        ),
        findsNothing,
      );

      launcher.failure =
          const DriverPlanPaymentPageLaunchException(
            code: 'unavailable',
          );

      await tester.ensureVisible(openButton);
      await tester.tap(openButton);
      await tester.pumpAndSettle();

      expect(launcher.calls, 2);
      expect(controller.paymentPageReady, isTrue);
      expect(
        controller.paymentPageLaunchErrorMessage,
        '\u00d6deme sayfas\u0131 a\u00e7\u0131lamad\u0131. '
        'L\u00fctfen tekrar deneyin.',
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-checkout-launch-error'),
        ),
        findsOneWidget,
      );

      launcher.failure = null;

      await tester.ensureVisible(openButton);
      await tester.tap(openButton);
      await tester.pumpAndSettle();

      expect(launcher.calls, 3);
      expect(controller.paymentPageReady, isTrue);
      expect(
        controller.paymentPageLaunchErrorMessage,
        isNull,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-checkout-launch-error'),
        ),
        findsNothing,
      );
    },
  );
}

Future<void> _fillCheckoutForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-buyer-name')),
    'Test',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-buyer-surname')),
    'Buyer',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-buyer-identity-number')),
    '11111111111',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-buyer-email')),
    'buyer@example.test',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-buyer-registration-address')),
    'Registration Address',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-buyer-city')),
    'Istanbul',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-buyer-country')),
    'Turkey',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-buyer-zip-code')),
    '34000',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-billing-address')),
    'Billing Address',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-billing-contact-name')),
    'Test Buyer',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-billing-city')),
    'Istanbul',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-billing-country')),
    'Turkey',
  );
  await tester.enterText(
    find.byKey(const ValueKey('driver-plan-billing-zip-code')),
    '34000',
  );

  await tester.pump();
}

Future<DriverPlanPurchaseController> _showPanel(
  WidgetTester tester,
  _Gateway gateway,
) async {
  final controller = DriverPlanPurchaseController(
    gateway: gateway,
    requestIdFactory: () => 'request-1',
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverPlanPurchasePanel(controller: controller),
        ),
      ),
    ),
  );

  return controller;
}

DriverPlanCatalogSnapshot catalog() {
  return const DriverPlanCatalogSnapshot(
    catalogVersion: 'catalog_v1',
    plans: [
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.daily,
        enabled: true,
        amountMinor: 1234,
        currency: 'TRY',
      ),
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.weekly,
        enabled: false,
        amountMinor: 2345,
        currency: 'TRY',
      ),
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.monthly,
        enabled: true,
        amountMinor: 3456,
        currency: 'TRY',
      ),
      DriverPlanCatalogEntry(
        plan: DriverPassPlan.quarterly,
        enabled: true,
        amountMinor: 4567,
        currency: 'TRY',
      ),
    ],
  );
}

class _PaymentPageLauncher
    implements DriverPlanPaymentPageLauncher {
  int calls = 0;
  final List<Uri> urls = [];
  DriverPlanPaymentPageLaunchException? failure;

  @override
  Future<void> launchPaymentPage(Uri paymentPageUrl) async {
    calls++;
    urls.add(paymentPageUrl);

    if (failure case final error?) {
      throw error;
    }
  }
}
class _Gateway
    implements
        DriverPlanPurchaseGateway,
        DriverPlanCatalogGateway,
        DriverPlanCheckoutGateway {
  int catalogCalls = 0;
  int catalogFailures = 0;
  int prepareFailures = 0;
  int checkoutFailures = 0;
  int checkoutCalls = 0;
  Completer<DriverPlanCatalogSnapshot>? catalogCompleter;

  final List<String> checkoutOperationIds = [];
  final List<DriverPlanCheckoutBuyer> checkoutBuyers = [];
  final List<DriverPlanCheckoutBillingAddress> checkoutBillingAddresses = [];

  @override
  Future<DriverPlanCatalogSnapshot> load() async {
    catalogCalls++;

    if (catalogFailures > 0) {
      catalogFailures--;
      throw const DriverPlanCatalogException(code: 'unavailable');
    }

    if (catalogCompleter case final completer?) {
      return completer.future;
    }

    return catalog();
  }

  @override
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  }) async {
    if (prepareFailures > 0) {
      prepareFailures--;
      throw const DriverPlanPurchaseException(code: 'unavailable');
    }

    return PreparedDriverPlanPurchase(
      purchaseOperationId: List<String>.filled(64, 'a').join(),
      status: 'pending',
      catalogVersion: 'catalog_v1',
      plan: plan,
      amountMinor: 1234,
      currency: 'TRY',
    );
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

    if (checkoutFailures > 0) {
      checkoutFailures--;
      throw const DriverPlanPurchaseException(code: 'unavailable');
    }

    return InitializedDriverPlanCheckout(
      provider: 'iyzico_checkout_form',
      purchaseOperationId: purchaseOperationId,
      conversationId: 'conversation-1',
      token: 'token-1',
      paymentPageUrl: Uri.parse(
        'https://sandbox.example.test/payment',
      ),
    );
  }
}
