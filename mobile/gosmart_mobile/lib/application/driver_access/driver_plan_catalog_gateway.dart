import '../../domain/subscription/driver_pass_plan.dart';

class DriverPlanCatalogEntry {
  const DriverPlanCatalogEntry({
    required this.plan,
    required this.enabled,
    required this.amountMinor,
    required this.currency,
  });

  final DriverPassPlan plan;
  final bool enabled;
  final int amountMinor;
  final String currency;
}

class DriverPlanCatalogSnapshot {
  const DriverPlanCatalogSnapshot({
    required this.catalogVersion,
    required this.plans,
  });

  final String catalogVersion;
  final List<DriverPlanCatalogEntry> plans;

  DriverPlanCatalogEntry? entryFor(DriverPassPlan plan) {
    for (final entry in plans) {
      if (entry.plan == plan) {
        return entry;
      }
    }
    return null;
  }
}

class DriverPlanCatalogException implements Exception {
  const DriverPlanCatalogException({required this.code, this.reason});

  final String code;
  final String? reason;
}

abstract interface class DriverPlanCatalogGateway {
  Future<DriverPlanCatalogSnapshot> load();
}
