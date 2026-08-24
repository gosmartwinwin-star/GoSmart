enum DriverApplicationDocumentType {
  driverLicenseFront,
  driverLicenseBack,
  identityCardFront,
  identityCardBack,
  vehicleRegistration,
  driverProfilePhoto,
  criminalRecord;

  static const int _mib = 1024 * 1024;

  String get displayName => switch (this) {
    DriverApplicationDocumentType.driverLicenseFront => 'Sürücü Belgesi Ön Yüz',
    DriverApplicationDocumentType.driverLicenseBack =>
      'Sürücü Belgesi Arka Yüz',
    DriverApplicationDocumentType.identityCardFront => 'Kimlik Belgesi Ön Yüz',
    DriverApplicationDocumentType.identityCardBack => 'Kimlik Belgesi Arka Yüz',
    DriverApplicationDocumentType.vehicleRegistration => 'Araç Ruhsatı',
    DriverApplicationDocumentType.driverProfilePhoto =>
      'Sürücü Profil Fotoğrafı',
    DriverApplicationDocumentType.criminalRecord => 'Adli Sicil Kaydı',
  };

  bool get isProfilePhoto => this == driverProfilePhoto;

  List<String> get allowedContentTypes => List.unmodifiable(switch (this) {
    vehicleRegistration ||
    criminalRecord => const ['image/jpeg', 'image/png', 'application/pdf'],
    _ => const ['image/jpeg', 'image/png'],
  });

  int get maximumSizeBytes => (isProfilePhoto ? 5 : 10) * _mib;
}
