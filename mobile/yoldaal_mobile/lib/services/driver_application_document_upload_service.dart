import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../application/driver_application/driver_application_document_upload_gateway.dart';
import '../application/driver_application/driver_application_document_upload_result.dart';
import '../domain/driver_application/driver_application_document_type.dart';

abstract interface class DriverApplicationAuthUidProvider {
  String? get currentUid;
}

class FirebaseDriverApplicationAuthUidProvider
    implements DriverApplicationAuthUidProvider {
  final FirebaseAuth _auth;

  FirebaseDriverApplicationAuthUidProvider({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  @override
  String? get currentUid => _auth.currentUser?.uid;
}

class DriverApplicationStorageUploadResponse {
  final DateTime? uploadedAt;

  const DriverApplicationStorageUploadResponse({this.uploadedAt});
}

abstract interface class DriverApplicationStorageInvoker {
  Future<DriverApplicationStorageUploadResponse> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  });
}

class FirebaseDriverApplicationStorageInvoker
    implements DriverApplicationStorageInvoker {
  final FirebaseStorage _storage;

  FirebaseDriverApplicationStorageInvoker({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<DriverApplicationStorageUploadResponse> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  }) async {
    final snapshot = await _storage
        .ref(path)
        .putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            customMetadata: customMetadata,
          ),
        );
    final metadata = await snapshot.ref.getMetadata();
    return DriverApplicationStorageUploadResponse(
      uploadedAt: metadata.timeCreated,
    );
  }
}

class DriverApplicationDocumentUploadService
    implements DriverApplicationDocumentUploadGateway {
  final DriverApplicationAuthUidProvider _authUidProvider;
  final DriverApplicationStorageInvoker _storageInvoker;
  final DateTime Function() _now;

  DriverApplicationDocumentUploadService({
    DriverApplicationAuthUidProvider? authUidProvider,
    DriverApplicationStorageInvoker? storageInvoker,
    DateTime Function()? now,
  }) : _authUidProvider =
           authUidProvider ?? FirebaseDriverApplicationAuthUidProvider(),
       _storageInvoker =
           storageInvoker ?? FirebaseDriverApplicationStorageInvoker(),
       _now = now ?? DateTime.now;

  @override
  Future<DriverApplicationDocumentUploadResult> upload({
    required DriverApplicationDocumentType documentType,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final uid = _authUidProvider.currentUid;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Sürücü belgesi yüklemek için oturum gereklidir.');
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'Boş dosya yüklenemez.');
    }
    if (!documentType.allowedContentTypes.contains(contentType)) {
      throw ArgumentError.value(contentType, 'contentType');
    }
    if (bytes.length > documentType.maximumSizeBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Dosya çok büyük.');
    }

    final path = 'driverApplicationUploads/$uid/${documentType.name}/current';
    final response = await _storageInvoker.upload(
      path: path,
      bytes: bytes,
      contentType: contentType,
      customMetadata: {'documentType': documentType.name, 'ownerUid': uid},
    );
    // This time is upload UI information only. Final Firestore uploadedAt is
    // derived by the backend from immutable Storage object metadata.
    final uploadedAt = (response.uploadedAt ?? _now()).toUtc();
    return DriverApplicationDocumentUploadResult(
      documentType: documentType,
      storagePath: path,
      contentType: contentType,
      sizeBytes: bytes.length,
      uploadedAt: uploadedAt,
    );
  }
}
