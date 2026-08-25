import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/driver_access/driver_plan_purchase_gateway.dart';
import 'package:yoldaal_mobile/services/driver_plan_purchase_service.dart';

void main() {
  const operationId =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  const buyer = DriverPlanCheckoutBuyer(
    name: 'Test',
    surname: 'Driver',
    identityNumber: '11111111111',
    email: 'driver@example.test',
    registrationAddress: 'Test registration address',
    city: 'Istanbul',
    country: 'Turkey',
    zipCode: '34000',
  );

  const billingAddress = DriverPlanCheckoutBillingAddress(
    address: 'Test billing address',
    contactName: 'Test Driver',
    city: 'Istanbul',
    country: 'Turkey',
    zipCode: '34000',
  );

  test('checkout uses exact callable and transient minimal payload', () async {
    String? calledName;
    Map<String, Object?>? calledPayload;

    final service = DriverPlanPurchaseService(
      caller: (name, payload) async {
        calledName = name;
        calledPayload = payload;
        return checkoutResponse();
      },
    );

    final result = await service.initializeCheckout(
      purchaseOperationId: operationId,
      buyer: buyer,
      billingAddress: billingAddress,
    );

    expect(calledName, DriverPlanPurchaseService.checkoutCallableName);

    expect(calledPayload, <String, Object?>{
      'purchaseOperationId': operationId,
      'buyer': <String, Object?>{
        'name': 'Test',
        'surname': 'Driver',
        'identityNumber': '11111111111',
        'email': 'driver@example.test',
        'registrationAddress': 'Test registration address',
        'city': 'Istanbul',
        'country': 'Turkey',
        'zipCode': '34000',
      },
      'billingAddress': <String, Object?>{
        'address': 'Test billing address',
        'contactName': 'Test Driver',
        'city': 'Istanbul',
        'country': 'Turkey',
        'zipCode': '34000',
      },
    });

    for (final forbiddenKey in <String>[
      'driverId',
      'planId',
      'amountMinor',
      'currency',
      'gsmNumber',
      'callbackUrl',
      'ip',
    ]) {
      expect(calledPayload!.containsKey(forbiddenKey), isFalse);
    }

    expect(result.provider, 'iyzico_checkout_form');
    expect(result.purchaseOperationId, operationId);
    expect(result.conversationId, 'conversation-1');
    expect(result.token, 'checkout-token-1');
    expect(
      result.paymentPageUrl,
      Uri.parse('https://sandbox-cpp.iyzipay.com/checkoutform/payment/mock'),
    );
  });

  test('checkout rejects response for another purchase operation', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => checkoutResponse(
        purchaseOperationId:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
    );

    await expectLater(
      service.initializeCheckout(
        purchaseOperationId: operationId,
        buyer: buyer,
        billingAddress: billingAddress,
      ),
      throwsA(
        isA<DriverPlanPurchaseException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  for (final invalid in <String, Map<String, Object?>>{
    'provider': checkoutResponse(provider: 'other-provider'),
    'conversation': checkoutResponse(conversationId: '   '),
    'token': checkoutResponse(token: ''),
    'http-url': checkoutResponse(paymentPageUrl: 'http://example.test/payment'),
    'relative-url': checkoutResponse(paymentPageUrl: '/checkout/payment'),
    'extra-field': <String, Object?>{...checkoutResponse(), 'unexpected': true},
  }.entries) {
    test('checkout ${invalid.key} response fails closed', () async {
      final service = DriverPlanPurchaseService(
        caller: (_, _) async => invalid.value,
      );

      await expectLater(
        service.initializeCheckout(
          purchaseOperationId: operationId,
          buyer: buyer,
          billingAddress: billingAddress,
        ),
        throwsA(
          isA<DriverPlanPurchaseException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    });
  }

  test('checkout preserves safe Firebase code and reason', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => throw _TestFunctionsException(
        code: 'failed-precondition',
        details: <String, Object?>{'reason': 'driver_verified_phone_required'},
      ),
    );

    await expectLater(
      service.initializeCheckout(
        purchaseOperationId: operationId,
        buyer: buyer,
        billingAddress: billingAddress,
      ),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having(
              (error) => error.reason,
              'reason',
              'driver_verified_phone_required',
            ),
      ),
    );
  });

  test('checkout sanitizes unknown Firebase failure details', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => throw _TestFunctionsException(
        code: 'secret-provider-code',
        details: <String, Object?>{'reason': 'RAW SECRET DETAIL'},
      ),
    );

    await expectLater(
      service.initializeCheckout(
        purchaseOperationId: operationId,
        buyer: buyer,
        billingAddress: billingAddress,
      ),
      throwsA(
        isA<DriverPlanPurchaseException>()
            .having((error) => error.code, 'code', 'unavailable')
            .having((error) => error.reason, 'reason', isNull),
      ),
    );
  });

  test('unexpected checkout client failure becomes unavailable', () async {
    final service = DriverPlanPurchaseService(
      caller: (_, _) async => throw StateError('transport secret'),
    );

    await expectLater(
      service.initializeCheckout(
        purchaseOperationId: operationId,
        buyer: buyer,
        billingAddress: billingAddress,
      ),
      throwsA(
        isA<DriverPlanPurchaseException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });
}

Map<String, Object?> checkoutResponse({
  String provider = 'iyzico_checkout_form',
  String purchaseOperationId =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String conversationId = 'conversation-1',
  String token = 'checkout-token-1',
  String paymentPageUrl =
      'https://sandbox-cpp.iyzipay.com/checkoutform/payment/mock',
}) => <String, Object?>{
  'provider': provider,
  'purchaseOperationId': purchaseOperationId,
  'conversationId': conversationId,
  'token': token,
  'paymentPageUrl': paymentPageUrl,
};

class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException({required super.code, super.details})
    : super(message: 'safe test failure');
}
