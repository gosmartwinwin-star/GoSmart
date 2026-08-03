final class AdminAuthenticationException implements Exception {
  const AdminAuthenticationException(this.code);
  final String code;
}

final class AdminPanelException implements Exception {
  const AdminPanelException(this.code, {this.reason});
  final String code;
  final String? reason;
}

String adminAuthMessage(Object error) => switch (error) {
  AdminAuthenticationException(code: 'invalid_credentials') =>
    'E-posta veya parola doğrulanamadı.',
  AdminAuthenticationException(code: 'admin_access_required') =>
    'Bu hesabın yönetim paneline erişim yetkisi bulunmuyor.',
  AdminAuthenticationException(code: 'session_expired') =>
    'Oturumunuz sona erdi. Lütfen tekrar giriş yapın.',
  _ => 'Giriş şu anda tamamlanamadı. Lütfen tekrar deneyin.',
};

String adminPanelMessage(Object error) {
  final reason = error is AdminPanelException ? error.reason : null;
  return switch (reason) {
    'authentication_required' =>
      'Oturumunuz sona erdi. Lütfen tekrar giriş yapın.',
    'admin_access_required' =>
      'Bu hesabın yönetim paneline erişim yetkisi bulunmuyor.',
    'invalid_admin_list_payload' => 'Başvuru listesi isteği doğrulanamadı.',
    'invalid_review_details_payload' =>
      'Başvuru ayrıntısı isteği doğrulanamadı.',
    'driver_application_not_found' => 'Başvuru bulunamadı.',
    'stale_driver_application_review' =>
      'Başvuru siz görüntülerken güncellendi. Lütfen yeniden yükleyin.',
    'driver_application_review_data_invalid' =>
      'Başvuru bilgileri doğrulanamadı.',
    'driver_application_list_failed' => 'Başvurular şu anda yüklenemedi.',
    'driver_application_details_failed' =>
      'Başvuru ayrıntıları şu anda yüklenemedi.',
    'driver_application_review_audit_failed' =>
      'Görüntüleme kaydı oluşturulamadı.',
    _ => 'İşlem şu anda tamamlanamadı. Lütfen tekrar deneyin.',
  };
}
