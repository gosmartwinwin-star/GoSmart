import 'package:cloud_functions/cloud_functions.dart';

import '../application/driver_access/driver_plan_purchase_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import '../domain/subscription/driver_pass_plan.dart';

typedef DriverPlanPurchaseHttpsCaller =
    Future<Object?> Function(String name, Map<String, Object?> payload);

class DriverPlanPurchaseService implements DriverPlanPurchaseGateway {
  DriverPlanPurchaseService({
    FirebaseFunctions? functions,
    DriverPlanPurchaseHttpsCaller? caller,
  }) : _caller =
           caller ??
           _firebaseCaller(functions ?? FirebaseFunctionsRegistry.client);

  static const callableName = 'prepareDriverPlanPurchase';

  final DriverPlanPurchaseHttpsCaller _caller;

  static DriverPlanPurchaseHttpsCaller _firebaseCaller(
    FirebaseFunctions functions,
  ) {
    return (name, payload) async {
      final result = await functions.httpsCallable(name).call(payload);
      return result.data;
    };
  }

  @override
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  }) async {
    try {
      final response = await _caller(callableName, <String, Object?>{
        'planId': plan.name,
        'requestId': requestId,
      });

      return _parseResponse(response, requestedPlan: plan);
    } on FirebaseFunctionsException catch (error) {
      throw DriverPlanPurchaseException(
        code: _safeFunctionCode(error.code),
        reason: _safeReason(error.details),
      );
    } on DriverPlanPurchaseException {
      rethrow;
    } catch (_) {
      throw const DriverPlanPurchaseException(code: 'unavailable');
    }
  }
}

PreparedDriverPlanPurchase _parseResponse(
  Object? value, {
  required DriverPassPlan requestedPlan,
}) {
  if (value is! Map) {
    throw const DriverPlanPurchaseException(code: 'invalid-response');
  }

  final purchaseOperationId = value['purchaseOperationId'];
  final status = value['status'];
  final catalogVersion = value['catalogVersion'];
  final planId = value['planId'];
  final amountMinor = value['amountMinor'];
  final currency = value['currency'];

  if (purchaseOperationId is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(purchaseOperationId)) {
    throw const DriverPlanPurchaseException(code: 'invalid-response');
  }

  if (status != 'pending') {
    throw const DriverPlanPurchaseException(code: 'invalid-response');
  }

  if (catalogVersion is! String ||
      catalogVersion.isEmpty ||
      catalogVersion.length > 128 ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(catalogVersion)) {
    throw const DriverPlanPurchaseException(code: 'invalid-response');
  }

  if (planId is! String) {
    throw const DriverPlanPurchaseException(code: 'invalid-response');
  }

  final plan = switch (planId) {
    'daily' => DriverPassPlan.daily,
    'weekly' => DriverPassPlan.weekly,
    'monthly' => DriverPassPlan.monthly,
    'quarterly' => DriverPassPlan.quarterly,
    _ => throw const DriverPlanPurchaseException(code: 'invalid-response'),
  };

  if (plan != requestedPlan) {
    throw const DriverPlanPurchaseException(code: 'invalid-response');
  }

  if (amountMinor is! int ||
      amountMinor < 0 ||
      amountMinor > 9007199254740991) {
    throw const DriverPlanPurchaseException(code: 'invalid-response');
  }

  if (currency is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
    throw const DriverPlanPurchaseException(code: 'invalid-response');
  }

  return PreparedDriverPlanPurchase(
    purchaseOperationId: purchaseOperationId,
    status: status as String,
    catalogVersion: catalogVersion,
    plan: plan,
    amountMinor: amountMinor,
    currency: currency,
  );
}

String _safeFunctionCode(String value) {
  const allowed = <String>{
    'unauthenticated',
    'permission-denied',
    'invalid-argument',
    'failed-precondition',
    'already-exists',
    'not-found',
    'resource-exhausted',
    'deadline-exceeded',
    'aborted',
    'unavailable',
    'internal',
  };

  return allowed.contains(value) ? value : 'unavailable';
}

String? _safeReason(Object? details) {
  if (details is! Map) {
    return null;
  }

  final reason = details['reason'];

  if (reason is! String || !RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(reason)) {
    return null;
  }

  return reason;
}
