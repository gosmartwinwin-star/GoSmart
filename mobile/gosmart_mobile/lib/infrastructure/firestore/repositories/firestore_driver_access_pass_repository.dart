import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../application/driver_access/driver_access_pass_repository.dart';
import '../../../domain/subscription/driver_access_pass.dart';
import '../firestore_collections.dart';
import '../mappers/driver_access_pass_firestore_mapper.dart';

class FirestoreDriverAccessPassRepository
    implements DriverAccessPassRepository {
  final FirebaseFirestore _firestore;

  FirestoreDriverAccessPassRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<DriverAccessPass?> findLatestForDriver(String driverId) async {
    if (driverId.trim().isEmpty) {
      throw ArgumentError.value(driverId, 'driverId', 'Boş olamaz.');
    }
    final snapshot = await _firestore
        .collection(FirestoreCollections.driverAccessPasses)
        .where('driverId', isEqualTo: driverId)
        .orderBy('purchasedAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final document = snapshot.docs.single;
    return mapDriverAccessPassDocument(
      documentId: document.id,
      data: document.data(),
    );
  }
}
