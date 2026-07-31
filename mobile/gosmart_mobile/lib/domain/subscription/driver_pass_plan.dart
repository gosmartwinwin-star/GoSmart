enum DriverPassPlan { daily, weekly, monthly, quarterly }

extension DriverPassPlanDisplayName on DriverPassPlan {
  String get displayName {
    switch (this) {
      case DriverPassPlan.daily:
        return 'Günlük';
      case DriverPassPlan.weekly:
        return 'Haftalık';
      case DriverPassPlan.monthly:
        return 'Aylık';
      case DriverPassPlan.quarterly:
        return '3 Aylık';
    }
  }
}
