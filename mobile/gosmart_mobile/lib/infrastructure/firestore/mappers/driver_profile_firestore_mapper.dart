import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/driver/driver_profile.dart';
import '../../../domain/driver/driver_profile_status.dart';

DriverProfile mapDriverProfileDocument({
  required String documentId,
  required Map<String, Object?> data,
}) {
  try {
    return DriverProfile(
      id: _documentId(documentId),
      authUserId: _requiredString(data, 'authUserId'),
      status: _profileStatus(data['status']),
      createdAt: _requiredTimestamp(data, 'createdAt'),
      approvedAt: _optionalTimestamp(data, 'approvedAt'),
      suspendedAt: _optionalTimestamp(data, 'suspendedAt'),
    );
  } on FormatException {
    rethrow;
  } on ArgumentError {
    throw const FormatException(
      'Sürücü profili domain kurallarını ihlal ediyor.',
    );
  }
}

String _documentId(String value) {
  if (value.trim().isEmpty) {
    throw const FormatException('Belge kimliği geçersiz.');
  }
  return value;
}

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field alanı geçersiz.');
  }
  return value;
}

DateTime _requiredTimestamp(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! Timestamp) throw FormatException('$field alanı geçersiz.');
  return value.toDate().toUtc();
}

DateTime? _optionalTimestamp(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value == null) return null;
  if (value is! Timestamp) throw FormatException('$field alanı geçersiz.');
  return value.toDate().toUtc();
}

DriverProfileStatus _profileStatus(Object? value) {
  if (value is! String) throw const FormatException('status alanı geçersiz.');
  return switch (value) {
    'pendingReview' => DriverProfileStatus.pendingReview,
    'approved' => DriverProfileStatus.approved,
    'suspended' => DriverProfileStatus.suspended,
    'rejected' => DriverProfileStatus.rejected,
    'deactivated' => DriverProfileStatus.deactivated,
    _ => throw const FormatException('Bilinmeyen sürücü profil durumu.'),
  };
}
