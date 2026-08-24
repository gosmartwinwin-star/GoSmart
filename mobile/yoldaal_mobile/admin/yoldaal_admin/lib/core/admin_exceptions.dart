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
    'invalid_driver_application_review_events_payload' =>
      'İnceleme geçmişi isteği doğrulanamadı.',
    'driver_application_review_events_data_invalid' =>
      'İnceleme geçmişi bilgileri doğrulanamadı.',
    'driver_application_review_events_failed' =>
      'İnceleme geçmişi şu anda yüklenemedi.',
    'driver_application_review_audit_failed' =>
      'Görüntüleme kaydı oluşturulamadı.',
    'invalid_document_review_url_payload' =>
      'Belge görüntüleme isteği doğrulanamadı.',
    'driver_application_document_not_found' => 'Belge bulunamadı.',
    'driver_application_document_data_invalid' =>
      'Belge bilgileri doğrulanamadı.',
    'document_review_url_unavailable' => 'Belge şu anda görüntülenemedi.',
    'invalid_review_payload' => 'İnceleme isteği doğrulanamadı.',
    'invalid_document_rejection_reason' =>
      'Belge yeniden yükleme nedeni seçilmelidir.',
    'invalid_application_rejection_reason' =>
      'Başvuru ret nedeni seçilmelidir.',
    'driver_application_documents_not_approved' =>
      'Başvurunun onaylanabilmesi için tüm belgeler onaylanmalıdır.',
    'driver_application_not_pending' => 'Başvuru artık incelemeye açık değil.',
    'driver_profile_exists' => 'Bu hesap için sürücü profili zaten mevcut.',
    'driver_application_review_persistence_failed' =>
      'İnceleme kararı şu anda kaydedilemedi.',
    _ => 'İşlem şu anda tamamlanamadı. Lütfen tekrar deneyin.',
  };
}
