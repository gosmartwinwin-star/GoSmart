import 'dart:typed_data';

import '../../domain/driver_application/driver_application_document_type.dart';
import 'driver_application_document_upload_result.dart';

abstract interface class DriverApplicationDocumentUploadGateway {
  Future<DriverApplicationDocumentUploadResult> upload({
    required DriverApplicationDocumentType documentType,
    required Uint8List bytes,
    required String contentType,
  });
}
