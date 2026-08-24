enum DriverReturnRouteStatus {
  draft,
  active,
  paused,
  completed,
  expired,
  cancelled,
}

extension DriverReturnRouteStatusDisplayName on DriverReturnRouteStatus {
  String get displayName {
    switch (this) {
      case DriverReturnRouteStatus.draft:
        return 'Taslak';
      case DriverReturnRouteStatus.active:
        return 'Aktif';
      case DriverReturnRouteStatus.paused:
        return 'Duraklatıldı';
      case DriverReturnRouteStatus.completed:
        return 'Tamamlandı';
      case DriverReturnRouteStatus.expired:
        return 'Süresi Doldu';
      case DriverReturnRouteStatus.cancelled:
        return 'İptal Edildi';
    }
  }
}
