class DriverApplicationLegalContent {
  final bool isFinalized;
  final String kvkkTitle;
  final String kvkkDraftNotice;
  final String termsTitle;
  final String termsDraftNotice;

  const DriverApplicationLegalContent({
    this.isFinalized = false,
    this.kvkkTitle = 'KVKK Aydınlatma Metni',
    this.kvkkDraftNotice =
        'Taslak metin — production kullanımı için hukuk onayı gereklidir.',
    this.termsTitle = 'GoSmart Kullanım Koşulları',
    this.termsDraftNotice =
        'Taslak metin — production kullanımı için hukuk onayı gereklidir.',
  });
}
