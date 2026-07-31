import 'driver_profile_status.dart';

class DriverProfile {
  final String id;
  final String authUserId;
  final DriverProfileStatus status;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? suspendedAt;

  const DriverProfile._({
    required this.id,
    required this.authUserId,
    required this.status,
    required this.createdAt,
    required this.approvedAt,
    required this.suspendedAt,
  });

  factory DriverProfile({
    required String id,
    required String authUserId,
    required DriverProfileStatus status,
    required DateTime createdAt,
    DateTime? approvedAt,
    DateTime? suspendedAt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Boş olamaz.');
    }
    if (authUserId.trim().isEmpty) {
      throw ArgumentError.value(authUserId, 'authUserId', 'Boş olamaz.');
    }
    if (status == DriverProfileStatus.approved && approvedAt == null) {
      throw ArgumentError(
        'Onaylı profilde approvedAt zorunludur.',
        'approvedAt',
      );
    }
    if (status == DriverProfileStatus.suspended) {
      if (approvedAt == null) {
        throw ArgumentError(
          'Askıya alınmış profilde approvedAt zorunludur.',
          'approvedAt',
        );
      }
      if (suspendedAt == null) {
        throw ArgumentError(
          'Askıya alınmış profilde suspendedAt zorunludur.',
          'suspendedAt',
        );
      }
    }
    if (suspendedAt != null && approvedAt == null) {
      throw ArgumentError(
        'suspendedAt için approvedAt zorunludur.',
        'approvedAt',
      );
    }
    if (approvedAt != null && approvedAt.isBefore(createdAt)) {
      throw ArgumentError(
        'approvedAt, createdAt değerinden önce olamaz.',
        'approvedAt',
      );
    }
    if (suspendedAt != null && suspendedAt.isBefore(createdAt)) {
      throw ArgumentError(
        'suspendedAt, createdAt değerinden önce olamaz.',
        'suspendedAt',
      );
    }
    if (suspendedAt != null && suspendedAt.isBefore(approvedAt!)) {
      throw ArgumentError(
        'suspendedAt, approvedAt değerinden önce olamaz.',
        'suspendedAt',
      );
    }

    return DriverProfile._(
      id: id,
      authUserId: authUserId,
      status: status,
      createdAt: createdAt,
      approvedAt: approvedAt,
      suspendedAt: suspendedAt,
    );
  }

  bool get isApproved => status == DriverProfileStatus.approved;
}
