class DriverPlanPaymentPageLaunchException implements Exception {
  const DriverPlanPaymentPageLaunchException({required this.code});

  final String code;
}

abstract interface class DriverPlanPaymentPageLauncher {
  Future<void> launchPaymentPage(Uri paymentPageUrl);
}