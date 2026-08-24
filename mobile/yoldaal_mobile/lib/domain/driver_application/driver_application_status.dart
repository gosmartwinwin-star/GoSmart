enum DriverApplicationStatus {
  pendingReview,
  approved,
  rejected,
  withdrawn;

  String get displayName => switch (this) {
    DriverApplicationStatus.pendingReview => 'İnceleme Bekliyor',
    DriverApplicationStatus.approved => 'Onaylandı',
    DriverApplicationStatus.rejected => 'Onaylanmadı',
    DriverApplicationStatus.withdrawn => 'Geri Çekildi',
  };
}
