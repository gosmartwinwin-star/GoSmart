enum DriverApplicationDocumentStatus {
  missing,
  uploaded,
  pendingReview,
  approved,
  reuploadRequired;

  String get displayName => switch (this) {
    DriverApplicationDocumentStatus.missing => 'Yüklenmedi',
    DriverApplicationDocumentStatus.uploaded => 'Yüklendi',
    DriverApplicationDocumentStatus.pendingReview => 'İnceleme Bekliyor',
    DriverApplicationDocumentStatus.approved => 'Onaylandı',
    DriverApplicationDocumentStatus.reuploadRequired => 'Yeniden Yüklenmeli',
  };
}
