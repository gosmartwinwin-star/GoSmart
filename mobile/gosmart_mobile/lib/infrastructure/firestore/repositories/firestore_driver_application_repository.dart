import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../application/driver_application/driver_application_repository.dart';
import '../../../domain/driver_application/driver_application_status.dart';

class FirestoreDriverApplicationRepository
    implements DriverApplicationRepository {
  final FirebaseFirestore _firestore;
  FirestoreDriverApplicationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<DriverApplicationSummary?> findForAuthenticatedUser(
    String userId,
  ) async {
    if (userId.trim().isEmpty) throw ArgumentError.value(userId, 'userId');
    final snapshot = await _firestore
        .collection('driverApplications')
        .doc(userId)
        .get();
    if (!snapshot.exists) return null;
    final data = snapshot.data();
    if (data == null || data['authUserId'] != userId) {
      throw const FormatException('Başvuru kaydı geçersiz.');
    }
    final timestamp = data['submittedAt'];
    final version = data['submissionVersion'];
    if (timestamp is! Timestamp || version is! int || version <= 0) {
      throw const FormatException('Başvuru kaydı geçersiz.');
    }
    final status = switch (data['status']) {
      'pendingReview' => DriverApplicationStatus.pendingReview,
      'approved' => DriverApplicationStatus.approved,
      'rejected' => DriverApplicationStatus.rejected,
      'withdrawn' => DriverApplicationStatus.withdrawn,
      _ => throw const FormatException('Başvuru durumu geçersiz.'),
    };
    return DriverApplicationSummary(
      status: status,
      submittedAt: timestamp.toDate().toUtc(),
      submissionVersion: version,
    );
  }
}
