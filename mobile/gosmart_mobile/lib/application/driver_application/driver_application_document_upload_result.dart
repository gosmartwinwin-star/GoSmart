import '../../domain/driver_application/driver_application_document_type.dart';

class DriverApplicationDocumentUploadResult {
  final DriverApplicationDocumentType documentType;
  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final DateTime uploadedAt;

  DriverApplicationDocumentUploadResult({
    required this.documentType,
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    required DateTime uploadedAt,
  }) : uploadedAt = uploadedAt.toUtc() {
    if (storagePath.trim().isEmpty) {
      throw ArgumentError.value(storagePath, 'storagePath');
    }
    if (!documentType.allowedContentTypes.contains(contentType)) {
      throw ArgumentError.value(contentType, 'contentType');
    }
    if (sizeBytes <= 0 || sizeBytes > documentType.maximumSizeBytes) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes');
    }
  }
}
