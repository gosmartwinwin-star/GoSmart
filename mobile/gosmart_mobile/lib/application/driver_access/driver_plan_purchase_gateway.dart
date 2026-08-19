import '../../domain/subscription/driver_pass_plan.dart';

class PreparedDriverPlanPurchase {
  const PreparedDriverPlanPurchase({
    required this.purchaseOperationId,
    required this.status,
    required this.catalogVersion,
    required this.plan,
    required this.amountMinor,
    required this.currency,
  });

  final String purchaseOperationId;
  final String status;
  final String catalogVersion;
  final DriverPassPlan plan;
  final int amountMinor;
  final String currency;
}

class DriverPlanPurchaseException implements Exception {
  const DriverPlanPurchaseException({required this.code, this.reason});

  final String code;
  final String? reason;
}

abstract interface class DriverPlanPurchaseGateway {
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  });
}
