import 'package:cloud_functions/cloud_functions.dart';

import '../application/driver_access/driver_plan_catalog_gateway.dart';
import '../domain/subscription/driver_pass_plan.dart';
import '../core/firebase/firebase_functions_registry.dart';

typedef DriverPlanCatalogHttpsCaller =
    Future<Object?> Function(String name, Map<String, dynamic> payload);

class DriverPlanCatalogService implements DriverPlanCatalogGateway {
  DriverPlanCatalogService({
    FirebaseFunctions? functions,
    DriverPlanCatalogHttpsCaller? caller,
  }) : _caller =
           caller ??
           _firebaseCaller(functions ?? FirebaseFunctionsRegistry.client);

  static const callableName = 'getDriverPlanCatalog';

  final DriverPlanCatalogHttpsCaller _caller;

  static DriverPlanCatalogHttpsCaller _firebaseCaller(
    FirebaseFunctions functions,
  ) {
    return (name, payload) async {
      final result = await functions.httpsCallable(name).call(payload);
      return result.data;
    };
  }

  @override
  Future<DriverPlanCatalogSnapshot> load() async {
    try {
      final raw = await _caller(callableName, const <String, dynamic>{});
      return _parseCatalog(raw);
    } on DriverPlanCatalogException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw DriverPlanCatalogException(
        code: _safeFunctionCode(error.code),
        reason: _safeReason(error.details),
      );
    } catch (_) {
      throw const DriverPlanCatalogException(code: 'unavailable');
    }
  }
}

DriverPlanCatalogSnapshot _parseCatalog(Object? raw) {
  final value = _exactMap(raw, const {'catalogVersion', 'plans'});

  final catalogVersion = value['catalogVersion'];
  final rawPlans = value['plans'];

  if (catalogVersion is! String ||
      catalogVersion.isEmpty ||
      catalogVersion.length > 128 ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(catalogVersion)) {
    throw const DriverPlanCatalogException(code: 'invalid-response');
  }

  if (rawPlans is! List || rawPlans.length != DriverPassPlan.values.length) {
    throw const DriverPlanCatalogException(code: 'invalid-response');
  }

  final plans = <DriverPlanCatalogEntry>[];

  for (var index = 0; index < DriverPassPlan.values.length; index++) {
    final expectedPlan = DriverPassPlan.values[index];

    final entry = _exactMap(rawPlans[index], const {
      'planId',
      'enabled',
      'amountMinor',
      'currency',
    });

    final planId = entry['planId'];
    final enabled = entry['enabled'];
    final amountMinor = entry['amountMinor'];
    final currency = entry['currency'];

    if (planId != expectedPlan.name ||
        enabled is! bool ||
        amountMinor is! int ||
        amountMinor < 0 ||
        amountMinor > 9007199254740991 ||
        currency is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const DriverPlanCatalogException(code: 'invalid-response');
    }

    plans.add(
      DriverPlanCatalogEntry(
        plan: expectedPlan,
        enabled: enabled,
        amountMinor: amountMinor,
        currency: currency,
      ),
    );
  }

  return DriverPlanCatalogSnapshot(
    catalogVersion: catalogVersion,
    plans: List.unmodifiable(plans),
  );
}

Map<String, Object?> _exactMap(Object? raw, Set<String> expectedKeys) {
  if (raw is! Map) {
    throw const DriverPlanCatalogException(code: 'invalid-response');
  }

  final value = <String, Object?>{};

  for (final entry in raw.entries) {
    final key = entry.key;

    if (key is! String || value.containsKey(key)) {
      throw const DriverPlanCatalogException(code: 'invalid-response');
    }

    value[key] = entry.value;
  }

  if (value.length != expectedKeys.length ||
      !value.keys.every(expectedKeys.contains)) {
    throw const DriverPlanCatalogException(code: 'invalid-response');
  }

  return value;
}

String _safeFunctionCode(String value) {
  const allowed = <String>{
    'unauthenticated',
    'permission-denied',
    'invalid-argument',
    'failed-precondition',
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
