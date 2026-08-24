enum DriverPassStatus { pending, active, expired, cancelled }

extension DriverPassStatusDisplayName on DriverPassStatus {
  String get displayName {
    switch (this) {
      case DriverPassStatus.pending:
        return 'Beklemede';
      case DriverPassStatus.active:
        return 'Aktif';
      case DriverPassStatus.expired:
        return 'Süresi Doldu';
      case DriverPassStatus.cancelled:
        return 'İptal Edildi';
    }
  }
}
