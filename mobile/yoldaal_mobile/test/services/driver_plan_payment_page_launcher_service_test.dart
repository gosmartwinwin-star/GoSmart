import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yoldaal_mobile/application/driver_access/driver_plan_payment_page_launcher.dart';
import 'package:yoldaal_mobile/services/driver_plan_payment_page_launcher_service.dart';

void main() {
  test('iyzico payment page launches only in external application mode', () async {
    Uri? capturedUrl;
    LaunchMode? capturedMode;

    final launcher = UrlLauncherDriverPlanPaymentPageLauncher(
      caller: (
        Uri url, {
        required LaunchMode mode,
      }) async {
        capturedUrl = url;
        capturedMode = mode;
        return true;
      },
    );

    final paymentPageUrl = Uri.parse(
      'https://sandbox-cpp.iyzipay.com?token=checkout-token',
    );

    await launcher.launchPaymentPage(paymentPageUrl);

    expect(capturedUrl, paymentPageUrl);
    expect(capturedMode, LaunchMode.externalApplication);
  });

  test('iyzipay apex host is accepted', () async {
    var calls = 0;

    final launcher = UrlLauncherDriverPlanPaymentPageLauncher(
      caller: (
        Uri url, {
        required LaunchMode mode,
      }) async {
        calls++;
        return true;
      },
    );

    await launcher.launchPaymentPage(
      Uri.parse('https://iyzipay.com/payment'),
    );

    expect(calls, 1);
  });

  test('non-iyzipay host fails closed without calling platform', () async {
    var calls = 0;

    final launcher = UrlLauncherDriverPlanPaymentPageLauncher(
      caller: (
        Uri url, {
        required LaunchMode mode,
      }) async {
        calls++;
        return true;
      },
    );

    await expectLater(
      launcher.launchPaymentPage(
        Uri.parse('https://attacker.example.com/payment'),
      ),
      throwsA(
        isA<DriverPlanPaymentPageLaunchException>().having(
          (error) => error.code,
          'code',
          'invalid-payment-page-url',
        ),
      ),
    );

    expect(calls, 0);
  });

  test('lookalike iyzipay suffix host fails closed', () async {
    var calls = 0;

    final launcher = UrlLauncherDriverPlanPaymentPageLauncher(
      caller: (
        Uri url, {
        required LaunchMode mode,
      }) async {
        calls++;
        return true;
      },
    );

    await expectLater(
      launcher.launchPaymentPage(
        Uri.parse('https://iyzipay.com.attacker.example/payment'),
      ),
      throwsA(
        isA<DriverPlanPaymentPageLaunchException>().having(
          (error) => error.code,
          'code',
          'invalid-payment-page-url',
        ),
      ),
    );

    expect(calls, 0);
  });

  test('http payment page fails closed', () async {
    var calls = 0;

    final launcher = UrlLauncherDriverPlanPaymentPageLauncher(
      caller: (
        Uri url, {
        required LaunchMode mode,
      }) async {
        calls++;
        return true;
      },
    );

    await expectLater(
      launcher.launchPaymentPage(
        Uri.parse('http://sandbox-cpp.iyzipay.com/payment'),
      ),
      throwsA(
        isA<DriverPlanPaymentPageLaunchException>().having(
          (error) => error.code,
          'code',
          'invalid-payment-page-url',
        ),
      ),
    );

    expect(calls, 0);
  });

  test('userinfo in payment page URL fails closed', () async {
    var calls = 0;

    final launcher = UrlLauncherDriverPlanPaymentPageLauncher(
      caller: (
        Uri url, {
        required LaunchMode mode,
      }) async {
        calls++;
        return true;
      },
    );

    await expectLater(
      launcher.launchPaymentPage(
        Uri.parse(
          'https://user:password@sandbox-cpp.iyzipay.com/payment',
        ),
      ),
      throwsA(
        isA<DriverPlanPaymentPageLaunchException>().having(
          (error) => error.code,
          'code',
          'invalid-payment-page-url',
        ),
      ),
    );

    expect(calls, 0);
  });

  test('platform false result becomes sanitized unavailable error', () async {
    final launcher = UrlLauncherDriverPlanPaymentPageLauncher(
      caller: (
        Uri url, {
        required LaunchMode mode,
      }) async {
        return false;
      },
    );

    await expectLater(
      launcher.launchPaymentPage(
        Uri.parse('https://sandbox-cpp.iyzipay.com/payment'),
      ),
      throwsA(
        isA<DriverPlanPaymentPageLaunchException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });

  test('platform exception becomes sanitized unavailable error', () async {
    final launcher = UrlLauncherDriverPlanPaymentPageLauncher(
      caller: (
        Uri url, {
        required LaunchMode mode,
      }) async {
        throw StateError('raw platform browser secret');
      },
    );

    await expectLater(
      launcher.launchPaymentPage(
        Uri.parse('https://sandbox-cpp.iyzipay.com/payment'),
      ),
      throwsA(
        isA<DriverPlanPaymentPageLaunchException>()
            .having(
              (error) => error.code,
              'code',
              'unavailable',
            )
            .having(
              (error) => error.toString(),
              'safe exception text',
              isNot(contains('raw platform browser secret')),
            ),
      ),
    );
  });
}