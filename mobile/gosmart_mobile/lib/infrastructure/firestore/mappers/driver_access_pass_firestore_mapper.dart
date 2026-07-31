import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/subscription/driver_access_pass.dart';
import '../../../domain/subscription/driver_pass_plan.dart';
import '../../../domain/subscription/driver_pass_status.dart';

DriverAccessPass mapDriverAccessPassDocument({
  required String documentId,
  required Map<String, Object?> data,
}) {
  try {
    return DriverAccessPass(
      id: _documentId(documentId),
      driverId: _requiredString(data, 'driverId'),
      plan: _passPlan(data['plan']),
      status: _passStatus(data['status']),
      purchasedAt: _requiredTimestamp(data, 'purchasedAt'),
      activatedAt: _optionalTimestamp(data, 'activatedAt'),
      expiresAt: _optionalTimestamp(data, 'expiresAt'),
    );
  } on FormatException {
    rethrow;
  } on ArgumentError {
    throw const FormatException(
      'Sürücü kontör kaydı domain kurallarını ihlal ediyor.',
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

DriverPassPlan _passPlan(Object? value) {
  if (value is! String) throw const FormatException('plan alanı geçersiz.');
  return switch (value) {
    'daily' => DriverPassPlan.daily,
    'weekly' => DriverPassPlan.weekly,
    'monthly' => DriverPassPlan.monthly,
    'quarterly' => DriverPassPlan.quarterly,
    _ => throw const FormatException('Bilinmeyen kontör planı.'),
  };
}

DriverPassStatus _passStatus(Object? value) {
  if (value is! String) throw const FormatException('status alanı geçersiz.');
  return switch (value) {
    'pending' => DriverPassStatus.pending,
    'active' => DriverPassStatus.active,
    'expired' => DriverPassStatus.expired,
    'cancelled' => DriverPassStatus.cancelled,
    _ => throw const FormatException('Bilinmeyen kontör durumu.'),
  };
}
