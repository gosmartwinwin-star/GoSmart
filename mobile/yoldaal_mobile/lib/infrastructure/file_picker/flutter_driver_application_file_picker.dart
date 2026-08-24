import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';

import '../../application/driver_application/driver_application_file_picker.dart';
import '../../domain/driver_application/driver_application_document_type.dart';

class FlutterDriverApplicationFilePicker
    implements DriverApplicationFilePicker {
  final ImagePicker _imagePicker;

  FlutterDriverApplicationFilePicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  @override
  Future<PickedDriverApplicationFile?> pickFromCamera({
    required DriverApplicationDocumentType documentType,
  }) => _pickImage(documentType, ImageSource.camera);

  @override
  Future<PickedDriverApplicationFile?> pickFromGallery({
    required DriverApplicationDocumentType documentType,
  }) => _pickImage(documentType, ImageSource.gallery);

  Future<PickedDriverApplicationFile?> _pickImage(
    DriverApplicationDocumentType documentType,
    ImageSource source,
  ) async {
    final selected = await _imagePicker.pickImage(source: source);
    if (selected == null) return null;
    return validatePickedDriverApplicationFile(
      documentType: documentType,
      bytes: await selected.readAsBytes(),
    );
  }

  @override
  Future<PickedDriverApplicationFile?> pickPdf({
    required DriverApplicationDocumentType documentType,
  }) async {
    if (!documentType.allowedContentTypes.contains('application/pdf')) {
      throw const FormatException('Bu belge için PDF desteklenmiyor.');
    }
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'PDF',
          extensions: ['pdf'],
          mimeTypes: ['application/pdf'],
        ),
      ],
    );
    if (selected == null) return null;
    final Uint8List bytes = await selected.readAsBytes();
    return validatePickedDriverApplicationFile(
      documentType: documentType,
      bytes: bytes,
    );
  }
}
