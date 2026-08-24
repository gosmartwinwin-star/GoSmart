import 'package:intl/intl.dart';

final _date = DateFormat('dd.MM.yyyy HH:mm');
String formatAdminDate(DateTime value) => _date.format(value.toLocal());

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

String rejectionReasonLabel(String? code) => switch (code) {
  null => '—',
  'personal_information_invalid' => 'Kişisel bilgiler uygun değil.',
  'vehicle_information_invalid' => 'Araç bilgileri uygun değil.',
  'document_information_mismatch' => 'Belge bilgileri eşleşmiyor.',
  'eligibility_requirements_not_met' => 'Uygunluk koşulları sağlanmıyor.',
  'duplicate_application' => 'Tekrarlanan başvuru.',
  'application_information_incomplete' => 'Başvuru bilgileri eksik.',
  'document_reupload_required' => 'Belgenin yeniden yüklenmesi gerekiyor.',
  'unreadable_document' => 'Belge okunamıyor.',
  'incomplete_document' => 'Belge eksik.',
  'expired_document' => 'Belgenin geçerlilik süresi dolmuş.',
  'information_mismatch' => 'Bilgiler eşleşmiyor.',
  'wrong_document' => 'Yanlış belge yüklenmiş.',
  'unsupported_document' => 'Belge biçimi desteklenmiyor.',
  _ => 'İnceleme açıklaması mevcut.',
};
