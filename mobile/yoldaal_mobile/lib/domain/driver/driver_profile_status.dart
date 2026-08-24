enum DriverProfileStatus {
  pendingReview,
  approved,
  suspended,
  rejected,
  deactivated;

  String get displayName => switch (this) {
    DriverProfileStatus.pendingReview => 'İnceleme Bekliyor',
    DriverProfileStatus.approved => 'Onaylandı',
    DriverProfileStatus.suspended => 'Askıya Alındı',
    DriverProfileStatus.rejected => 'Reddedildi',
    DriverProfileStatus.deactivated => 'Devre Dışı',
  };
}
