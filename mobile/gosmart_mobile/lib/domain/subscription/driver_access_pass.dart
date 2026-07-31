import 'driver_pass_plan.dart';
import 'driver_pass_status.dart';

class DriverAccessPass {
  final String id;
  final String driverId;
  final DriverPassPlan plan;
  final DriverPassStatus status;
  final DateTime purchasedAt;
  final DateTime? activatedAt;
  final DateTime? expiresAt;

  const DriverAccessPass._({
    required this.id,
    required this.driverId,
    required this.plan,
    required this.status,
    required this.purchasedAt,
    required this.activatedAt,
    required this.expiresAt,
  });

  factory DriverAccessPass({
    required String id,
    required String driverId,
    required DriverPassPlan plan,
    required DriverPassStatus status,
    required DateTime purchasedAt,
    DateTime? activatedAt,
    DateTime? expiresAt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Boş olamaz.');
    }
    if (driverId.trim().isEmpty) {
      throw ArgumentError.value(driverId, 'driverId', 'Boş olamaz.');
    }
    if (status == DriverPassStatus.active && activatedAt == null) {
      throw ArgumentError(
        'Aktif erişim paketinde activatedAt zorunludur.',
        'activatedAt',
      );
    }
    if (status == DriverPassStatus.active && expiresAt == null) {
      throw ArgumentError(
        'Aktif erişim paketinde expiresAt zorunludur.',
        'expiresAt',
      );
    }
    if (activatedAt != null &&
        expiresAt != null &&
        expiresAt.isBefore(activatedAt)) {
      throw ArgumentError(
        'expiresAt, activatedAt değerinden önce olamaz.',
        'expiresAt',
      );
    }

    return DriverAccessPass._(
      id: id,
      driverId: driverId,
      plan: plan,
      status: status,
      purchasedAt: purchasedAt,
      activatedAt: activatedAt,
      expiresAt: expiresAt,
    );
  }

  bool isActiveAt(DateTime now) {
    final activation = activatedAt;
    final expiration = expiresAt;

    return status == DriverPassStatus.active &&
        activation != null &&
        expiration != null &&
        !now.isBefore(activation) &&
        now.isBefore(expiration);
  }

  Duration remainingAt(DateTime now) {
    if (!isActiveAt(now)) return Duration.zero;

    final remaining = expiresAt!.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
