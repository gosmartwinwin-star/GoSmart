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
  testWidgets(
    'explicit status refresh appears only when payment page ready',
    (tester) async {
      final gateway = _Gateway();
      final controller = await _showPanel(tester, gateway);
      addTearDown(controller.dispose);

      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-refresh'),
        ),
        findsNothing,
      );

      controller.selectPlan(DriverPassPlan.daily);
      await controller.prepare();
      await controller.initializeCheckout(
        buyer: _statusBuyer(),
        billingAddress: _statusBillingAddress(),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-refresh'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'payment status loading disables explicit refresh',
    (tester) async {
      final gateway = _Gateway();
      final controller =
          await _showPaymentStatusReadyPanel(tester, gateway);
      addTearDown(controller.dispose);

      final completer = Completer<DriverPlanPaymentStatus>();
      gateway.statusCompleter = completer;

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );

      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pump();

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-loading'),
        ),
        findsOneWidget,
      );

      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNull,
      );

      completer.complete(
        DriverPlanPaymentStatus(
          purchaseOperationId:
              controller.initializedCheckout!.purchaseOperationId,
          outcome: DriverPlanPaymentOutcome.pending,
        ),
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'pending status renders pending key and stays refreshable',
    (tester) async {
      final gateway = _Gateway()
        ..statusOutcome = DriverPlanPaymentOutcome.pending;

      final controller =
          await _showPaymentStatusReadyPanel(tester, gateway);
      addTearDown(controller.dispose);

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );

      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-pending'),
        ),
        findsOneWidget,
      );

      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'paymentReview status renders review key and stays refreshable',
    (tester) async {
      final gateway = _Gateway()
        ..statusOutcome = DriverPlanPaymentOutcome.paymentReview;

      final controller =
          await _showPaymentStatusReadyPanel(tester, gateway);
      addTearDown(controller.dispose);

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );

      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-review'),
        ),
        findsOneWidget,
      );

      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'paymentFailed status renders failure key and disables refresh',
    (tester) async {
      final gateway = _Gateway()
        ..statusOutcome = DriverPlanPaymentOutcome.paymentFailed;

      final controller =
          await _showPaymentStatusReadyPanel(tester, gateway);
      addTearDown(controller.dispose);

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );

      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-failure'),
        ),
        findsOneWidget,
      );

      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'settled status renders success key and disables refresh',
    (tester) async {
      final gateway = _Gateway()
        ..statusOutcome = DriverPlanPaymentOutcome.settled;

      final controller =
          await _showPaymentStatusReadyPanel(tester, gateway);
      addTearDown(controller.dispose);

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );

      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-success'),
        ),
        findsOneWidget,
      );

      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'status read error renders separate status error key',
    (tester) async {
      final gateway = _Gateway()
        ..statusError =
            const DriverPlanPurchaseException(code: 'unavailable');

      final controller =
          await _showPaymentStatusReadyPanel(tester, gateway);
      addTearDown(controller.dispose);

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );

      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-error'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'status read error does not render payment failure',
    (tester) async {
      final gateway = _Gateway()
        ..statusError =
            const DriverPlanPurchaseException(code: 'unavailable');

      final controller =
          await _showPaymentStatusReadyPanel(tester, gateway);
      addTearDown(controller.dispose);

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );

      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-error'),
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-failure'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'browser launch alone does not render payment success',
    (tester) async {
      final gateway = _Gateway();
      final launcher = _PaymentPageLauncher();

      final controller = await _showPaymentStatusReadyPanel(
        tester,
        gateway,
        paymentPageLauncher: launcher,
      );
      addTearDown(controller.dispose);

      final open = find.byKey(
        const ValueKey('driver-plan-checkout-open'),
      );

      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();

      expect(launcher.calls, 1);
      expect(gateway.statusCalls, 0);

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-success'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'initState triggers recovery exactly once',
    (tester) async {
      final gateway = _Gateway();
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-panel-recovery-init',
      );
      addTearDown(controller.dispose);

      await _pumpRecoveryPanel(tester, controller);

      expect(gateway.recoveryCalls, 1);
    },
  );

  testWidgets(
    'controller replacement triggers recovery on new controller exactly once',
    (tester) async {
      final firstGateway = _Gateway();
      final secondGateway = _Gateway();
      final firstController = DriverPlanPurchaseController(
        gateway: firstGateway,
        requestIdFactory: () => 'request-panel-recovery-first',
      );
      final secondController = DriverPlanPurchaseController(
        gateway: secondGateway,
        requestIdFactory: () => 'request-panel-recovery-second',
      );
      addTearDown(firstController.dispose);
      addTearDown(secondController.dispose);

      await _pumpRecoveryPanel(tester, firstController);
      expect(firstGateway.recoveryCalls, 1);

      await _pumpRecoveryPanel(tester, secondController);

      expect(firstGateway.recoveryCalls, 1);
      expect(secondGateway.recoveryCalls, 1);
    },
  );

  testWidgets(
    'same controller rebuild does not retrigger failed recovery',
    (tester) async {
      final gateway = _Gateway()
        ..recoveryError =
            const DriverPlanPurchaseException(code: 'unavailable');
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-panel-recovery-same',
      );
      addTearDown(controller.dispose);

      await _pumpRecoveryPanel(tester, controller);
      expect(gateway.recoveryCalls, 1);

      await _pumpRecoveryPanel(tester, controller);

      expect(gateway.recoveryCalls, 1);
    },
  );

  testWidgets(
    'null recovery renders no recovered status UX',
    (tester) async {
      final gateway = _Gateway();
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-panel-recovery-null',
      );
      addTearDown(controller.dispose);

      await _pumpRecoveryPanel(tester, controller);

      expect(gateway.recoveryCalls, 1);
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-loading'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-pending'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-review'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-failure'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-success'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-error'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-refresh'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'recovered pending is visible and refreshable',
    (tester) async {
      final gateway = _Gateway()
        ..recoveryStatus =
            _recoveredStatus(DriverPlanPaymentOutcome.pending)
        ..statusOutcome = DriverPlanPaymentOutcome.paymentReview;
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-panel-recovery-pending',
      );
      addTearDown(controller.dispose);

      await _pumpRecoveryPanel(tester, controller);

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-pending'),
        ),
        findsOneWidget,
      );

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );
      expect(refresh, findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNotNull,
      );

      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(gateway.statusCalls, 1);
      expect(gateway.statusOperationIds, [_recoveredOperationId()]);
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-review'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'recovered paymentReview is visible and refreshable',
    (tester) async {
      final gateway = _Gateway()
        ..recoveryStatus =
            _recoveredStatus(DriverPlanPaymentOutcome.paymentReview);
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-panel-recovery-review',
      );
      addTearDown(controller.dispose);

      await _pumpRecoveryPanel(tester, controller);

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-review'),
        ),
        findsOneWidget,
      );

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );
      expect(refresh, findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'recovered paymentFailed is visible and terminal',
    (tester) async {
      final gateway = _Gateway()
        ..recoveryStatus =
            _recoveredStatus(DriverPlanPaymentOutcome.paymentFailed);
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-panel-recovery-failed',
      );
      addTearDown(controller.dispose);

      await _pumpRecoveryPanel(tester, controller);

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-failure'),
        ),
        findsOneWidget,
      );

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );
      expect(refresh, findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'recovered settled is visible and terminal',
    (tester) async {
      final gateway = _Gateway()
        ..recoveryStatus =
            _recoveredStatus(DriverPlanPaymentOutcome.settled);
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-panel-recovery-settled',
      );
      addTearDown(controller.dispose);

      await _pumpRecoveryPanel(tester, controller);

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-success'),
        ),
        findsOneWidget,
      );

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );
      expect(refresh, findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'recovery read error renders status error and not payment failure',
    (tester) async {
      final gateway = _Gateway()
        ..recoveryError =
            const DriverPlanPurchaseException(code: 'unavailable');
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        requestIdFactory: () => 'request-panel-recovery-error',
      );
      addTearDown(controller.dispose);

      await _pumpRecoveryPanel(tester, controller);

      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-error'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-failure'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-payment-status-refresh'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'recovered-only UX has no payment-page browser or provider artifacts',
    (tester) async {
      final gateway = _Gateway()
        ..recoveryStatus =
            _recoveredStatus(DriverPlanPaymentOutcome.pending);
      final launcher = _PaymentPageLauncher();
      final controller = DriverPlanPurchaseController(
        gateway: gateway,
        paymentPageLauncher: launcher,
        requestIdFactory: () => 'request-panel-recovery-security',
      );
      addTearDown(controller.dispose);

      await _pumpRecoveryPanel(tester, controller);

      expect(controller.prepared, isNull);
      expect(controller.initializedCheckout, isNull);
      expect(gateway.checkoutCalls, 0);
      expect(launcher.calls, 0);

      expect(
        find.byKey(const ValueKey('driver-plan-checkout-ready')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('driver-plan-checkout-open')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-checkout-browser-note'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('driver-plan-checkout-launch-error'),
        ),
        findsNothing,
      );
      expect(find.textContaining('token-1'), findsNothing);
      expect(find.textContaining('conversation-1'), findsNothing);
      expect(
        find.textContaining('https://sandbox.example.test/payment'),
        findsNothing,
      );
    },
  );
  testWidgets(
    'status UX never renders payment URL token or conversation id',
    (tester) async {
      final gateway = _Gateway()
        ..statusOutcome = DriverPlanPaymentOutcome.settled;

      final controller =
          await _showPaymentStatusReadyPanel(tester, gateway);
      addTearDown(controller.dispose);

      final refresh = find.byKey(
        const ValueKey('driver-plan-payment-status-refresh'),
      );

      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      final checkout = controller.initializedCheckout!;

      expect(
        find.textContaining(checkout.paymentPageUrl.toString()),
        findsNothing,
      );
      expect(
        find.textContaining(checkout.token),
        findsNothing,
      );
      expect(
        find.textContaining(checkout.conversationId),
        findsNothing,
      );
    },
  );
}

String _recoveredOperationId() =>
    List<String>.filled(64, 'c').join();

DriverPlanPaymentStatus _recoveredStatus(
  DriverPlanPaymentOutcome outcome,
) {
  return DriverPlanPaymentStatus(
    purchaseOperationId: _recoveredOperationId(),
    outcome: outcome,
  );
}

Future<void> _pumpRecoveryPanel(
  WidgetTester tester,
  DriverPlanPurchaseController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverPlanPurchasePanel(controller: controller),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}
Future<DriverPlanPurchaseController> _showPaymentStatusReadyPanel(
  WidgetTester tester,
  _Gateway gateway, {
  DriverPlanPaymentPageLauncher? paymentPageLauncher,
}) async {
  final controller = DriverPlanPurchaseController(
    gateway: gateway,
    paymentPageLauncher: paymentPageLauncher,
    requestIdFactory: () => 'request-panel-status',
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

  await tester.pumpAndSettle();

  controller.selectPlan(DriverPassPlan.daily);
  await controller.prepare();
  await controller.initializeCheckout(
    buyer: _statusBuyer(),
    billingAddress: _statusBillingAddress(),
  );

  await tester.pumpAndSettle();

  return controller;
}

DriverPlanCheckoutBuyer _statusBuyer() {
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

DriverPlanCheckoutBillingAddress _statusBillingAddress() {
  return const DriverPlanCheckoutBillingAddress(
    address: 'Test Billing Address',
    contactName: 'Test Buyer',
    city: 'Istanbul',
    country: 'Turkey',
    zipCode: '34000',
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
        DriverPlanCheckoutGateway,
        DriverPlanPaymentStatusGateway,
        DriverPlanPaymentStatusRecoveryGateway {
  int catalogCalls = 0;
  int catalogFailures = 0;
  int prepareFailures = 0;
  int checkoutFailures = 0;
  int checkoutCalls = 0;
  Completer<DriverPlanCatalogSnapshot>? catalogCompleter;

  final List<String> checkoutOperationIds = [];
  final List<DriverPlanCheckoutBuyer> checkoutBuyers = [];
  final List<DriverPlanCheckoutBillingAddress> checkoutBillingAddresses = [];

  int statusCalls = 0;
  final List<String> statusOperationIds = [];
  DriverPlanPaymentOutcome statusOutcome =
      DriverPlanPaymentOutcome.pending;
  DriverPlanPurchaseException? statusError;
  Completer<DriverPlanPaymentStatus>? statusCompleter;

  int recoveryCalls = 0;
  DriverPlanPaymentStatus? recoveryStatus;
  DriverPlanPurchaseException? recoveryError;
  Completer<DriverPlanPaymentStatus?>? recoveryCompleter;

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

  @override
  Future<DriverPlanPaymentStatus> getPaymentStatus({
    required String purchaseOperationId,
  }) async {
    statusCalls++;
    statusOperationIds.add(purchaseOperationId);

    if (statusError case final error?) {
      throw error;
    }

    if (statusCompleter case final completer?) {
      return completer.future;
    }

    return DriverPlanPaymentStatus(
      purchaseOperationId: purchaseOperationId,
      outcome: statusOutcome,
    );
  }

  @override
  Future<DriverPlanPaymentStatus?> getLatestPaymentStatus() async {
    recoveryCalls++;

    if (recoveryError case final error?) {
      throw error;
    }

    if (recoveryCompleter case final completer?) {
      return completer.future;
    }

    return recoveryStatus;
  }
}
