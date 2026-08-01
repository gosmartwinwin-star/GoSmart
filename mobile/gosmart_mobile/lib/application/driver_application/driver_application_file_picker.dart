import 'dart:typed_data';

import '../../domain/driver_application/driver_application_document_type.dart';

class PickedDriverApplicationFile {
  final Uint8List bytes;
  final String contentType;
  int get sizeBytes => bytes.length;

  PickedDriverApplicationFile({
    required this.bytes,
    required this.contentType,
  }) {
    if (bytes.isEmpty) throw ArgumentError.value(bytes, 'bytes');
  }
}

abstract interface class DriverApplicationFilePicker {
  Future<PickedDriverApplicationFile?> pickFromCamera({
    required DriverApplicationDocumentType documentType,
  });
  Future<PickedDriverApplicationFile?> pickFromGallery({
    required DriverApplicationDocumentType documentType,
  });
  Future<PickedDriverApplicationFile?> pickPdf({
    required DriverApplicationDocumentType documentType,
  });
}

String detectDriverApplicationContentType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length >= png.length &&
      List.generate(
        png.length,
        (index) => bytes[index] == png[index],
      ).every((matches) => matches)) {
    return 'image/png';
  }
  const pdf = [0x25, 0x50, 0x44, 0x46, 0x2d];
  if (bytes.length >= pdf.length &&
      List.generate(
        pdf.length,
        (index) => bytes[index] == pdf[index],
      ).every((matches) => matches)) {
    return 'application/pdf';
  }
  throw const FormatException('Desteklenmeyen dosya içeriği.');
}

PickedDriverApplicationFile validatePickedDriverApplicationFile({
  required DriverApplicationDocumentType documentType,
  required Uint8List bytes,
}) {
  final contentType = detectDriverApplicationContentType(bytes);
  if (!documentType.allowedContentTypes.contains(contentType)) {
    throw const FormatException('Belge türü desteklenmiyor.');
  }
  if (bytes.length > documentType.maximumSizeBytes) {
    throw const FormatException('Belge boyutu sınırı aşıldı.');
  }
  return PickedDriverApplicationFile(bytes: bytes, contentType: contentType);
}
