import 'package:url_launcher/url_launcher.dart';

import '../application/driver_access/driver_plan_payment_page_launcher.dart';

typedef DriverPlanUrlLaunchCaller =
    Future<bool> Function(Uri url, {required LaunchMode mode});

Future<bool> _launchPaymentPageUrl(
  Uri url, {
  required LaunchMode mode,
}) {
  return launchUrl(url, mode: mode);
}

class UrlLauncherDriverPlanPaymentPageLauncher
    implements DriverPlanPaymentPageLauncher {
  UrlLauncherDriverPlanPaymentPageLauncher({
    DriverPlanUrlLaunchCaller? caller,
  }) : _caller = caller ?? _launchPaymentPageUrl;

  final DriverPlanUrlLaunchCaller _caller;

  @override
  Future<void> launchPaymentPage(Uri paymentPageUrl) async {
    if (!_isAllowedPaymentPageUrl(paymentPageUrl)) {
      throw const DriverPlanPaymentPageLaunchException(
        code: 'invalid-payment-page-url',
      );
    }

    try {
      final launched = await _caller(
        paymentPageUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw const DriverPlanPaymentPageLaunchException(
          code: 'unavailable',
        );
      }
    } on DriverPlanPaymentPageLaunchException {
      rethrow;
    } catch (_) {
      throw const DriverPlanPaymentPageLaunchException(
        code: 'unavailable',
      );
    }
  }
}

bool _isAllowedPaymentPageUrl(Uri uri) {
  if (!uri.isAbsolute ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return false;
  }

  final host = uri.host.toLowerCase();

  return host == 'iyzipay.com' || host.endsWith('.iyzipay.com');
}